use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Json},
    routing::get,
    Router,
};
use secp256k1::{Message, PublicKey, Secp256k1, SecretKey};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::path::Path;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use tracing::info;

// Matches the Move struct: PriceUpdatePayload { price: u64 }
#[derive(Serialize, Deserialize)]
struct PriceUpdatePayload {
    price: u64,
}

// Matches Nautilus IntentMessage structure
#[derive(Serialize)]
struct IntentMessage<T> {
    intent: u8,
    timestamp_ms: u64,
    data: T,
}

// Response format for the client
#[derive(Serialize)]
struct SignedPriceResponse {
    price: u64,
    timestamp_ms: u64,
    signature: String, // hex-encoded
}

// CoinGecko API response structure
#[derive(Deserialize, Debug)]
struct CoinGeckoResponse {
    sui: CoinGeckoPrice,
}

#[derive(Deserialize, Debug)]
struct CoinGeckoPrice {
    usd: f64,
}

// Application state
struct AppState {
    signing_key: SecretKey,
    http_client: reqwest::Client,
}

// Intent scope constant (0 for personal intent)
const INTENT_SCOPE: u8 = 0;

async fn fetch_sui_price(http_client: &reqwest::Client) -> Result<f64, anyhow::Error> {
    let url = "https://api.coingecko.com/api/v3/simple/price?ids=sui&vs_currencies=usd";
    
    let response = http_client
        .get(url)
        .send()
        .await?
        .json::<CoinGeckoResponse>()
        .await?;
    
    Ok(response.sui.usd)
}

fn current_timestamp_ms() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("Time went backwards")
        .as_millis() as u64
}

// Sign the price data following Nautilus pattern
fn sign_price_data(
    signing_key: &SecretKey,
    price: u64,
    timestamp_ms: u64,
) -> Result<String, anyhow::Error> {
    let payload = PriceUpdatePayload { price };
    
    let intent_message = IntentMessage {
        intent: INTENT_SCOPE,
        timestamp_ms,
        data: payload,
    };
    
    // BCS serialize the IntentMessage
    let message_bytes = bcs::to_bytes(&intent_message)?;
    
    // Hash the message with SHA256 (we'll use hash flag 1 in Sui)
    use sha2::{Sha256, Digest};
    let hash = Sha256::digest(&message_bytes);
    let message = Message::from_digest_slice(&hash)?;
    
    // Sign with secp256k1
    let secp = Secp256k1::new();
    let signature = secp.sign_ecdsa(&message, signing_key);
    
    // Return hex-encoded signature (64 bytes: r + s)
    Ok(hex::encode(signature.serialize_compact()))
}

async fn get_signed_price(
    State(state): State<Arc<AppState>>,
) -> Result<Json<SignedPriceResponse>, (StatusCode, String)> {
    // Fetch current SUI price from CoinGecko
    let price_usd = fetch_sui_price(&state.http_client)
        .await
        .map_err(|e| {
            tracing::error!("Failed to fetch SUI price: {}", e);
            (StatusCode::SERVICE_UNAVAILABLE, format!("Failed to fetch price: {}", e))
        })?;
    
    // Convert to u64 with 6 decimal places precision
    let price = (price_usd * 1_000_000.0) as u64;
    
    // Get timestamp in milliseconds
    let timestamp_ms = current_timestamp_ms();
    
    info!("Fetched SUI price: ${:.6} (raw: {})", price_usd, price);
    
    // Sign the data
    let signature = sign_price_data(&state.signing_key, price, timestamp_ms)
        .map_err(|e| {
            tracing::error!("Failed to sign data: {}", e);
            (StatusCode::INTERNAL_SERVER_ERROR, format!("Signing failed: {}", e))
        })?;
    
    Ok(Json(SignedPriceResponse {
        price,
        timestamp_ms,
        signature,
    }))
}

async fn health_check() -> impl IntoResponse {
    Json(serde_json::json!({ "status": "ok" }))
}

async fn get_public_key(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let secp = Secp256k1::new();
    let public_key = PublicKey::from_secret_key(&secp, &state.signing_key);
    let pk_hex = hex::encode(public_key.serialize());
    Json(serde_json::json!({ 
        "public_key": pk_hex
    }))
}

fn load_signing_key_from_file<P: AsRef<Path>>(path: P) -> Result<SecretKey, anyhow::Error> {
    let key_bytes = fs::read(path)?;
    
    // secp256k1 private key is 32 bytes
    if key_bytes.len() != 32 {
        anyhow::bail!("Expected 32-byte secp256k1 private key, got {} bytes", key_bytes.len());
    }
    
    let signing_key = SecretKey::from_slice(&key_bytes)?;
    Ok(signing_key)
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize tracing
    tracing_subscriber::fmt::init();
    
    // Get key path from command line args
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: {} <path-to-secp256k1-key>", args[0]);
        std::process::exit(1);
    }
    let key_path = &args[1];
    
    info!("Loading secp256k1 signing key from: {}", key_path);
    let signing_key = load_signing_key_from_file(key_path)?;
    info!("Signing key loaded successfully");
    
    // Log public key for reference
    let secp = Secp256k1::new();
    let public_key = PublicKey::from_secret_key(&secp, &signing_key);
    info!("Public key (hex): {}", hex::encode(public_key.serialize()));
    
    // Create shared state
    let state = Arc::new(AppState {
        signing_key,
        http_client: reqwest::Client::new(),
    });
    
    // Build router
    let app = Router::new()
        .route("/health", get(health_check))
        .route("/price", get(get_signed_price))
        .route("/public-key", get(get_public_key))
        .with_state(state);
    
    // Start server
    let addr = "0.0.0.0:3000";
    info!("Starting server on {}", addr);
    
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    
    Ok(())
}
