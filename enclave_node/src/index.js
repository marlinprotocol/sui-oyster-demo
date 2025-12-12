import express from 'express';
import axios from 'axios';
import { sign, getPublicKey, hashes } from '@noble/secp256k1';
import { sha256 } from '@noble/hashes/sha2.js';
import { hmac } from '@noble/hashes/hmac.js';
import { createHash } from 'crypto';
import fs from 'fs';
import { bcs } from '@mysten/bcs';

// Configure @noble/secp256k1 to use @noble/hashes for SHA-256
hashes.sha256 = sha256;
hashes.hmacSha256 = (key, msg) => hmac(sha256, key, msg);

// Define the structures to match Move contract
const PriceUpdatePayload = bcs.struct('PriceUpdatePayload', {
  price: bcs.u64(),
});

// Define IntentMessage wrapper - using a generic function approach
function IntentMessage(DataType) {
  return bcs.struct('IntentMessage', {
    intent: bcs.u8(),
    timestamp_ms: bcs.u64(),
    data: DataType,
  });
}

// Create the specific IntentMessage for PriceUpdatePayload
const IntentMessagePriceUpdate = IntentMessage(PriceUpdatePayload);

// Intent scope constant (0 for personal intent)
const INTENT_SCOPE = 0;

// Application state
let signingKey = null;
const httpClient = axios.create();

/**
 * Fetch current SUI price from CoinGecko API
 */
async function fetchSuiPrice() {
  const url = 'https://api.coingecko.com/api/v3/simple/price?ids=sui&vs_currencies=usd';
  
  try {
    const response = await httpClient.get(url);
    return response.data.sui.usd;
  } catch (error) {
    console.error('Failed to fetch SUI price:', error.message);
    throw error;
  }
}

/**
 * Get current timestamp in milliseconds
 */
function currentTimestampMs() {
  return Date.now();
}

/**
 * Sign price data following Nautilus pattern with secp256k1
 */
function signPriceData(privateKey, price, timestampMs) {
  // Create payload matching Move struct
  const payload = {
    price: price, // u64 can be number, string, or bigint - BCS handles conversion
  };
  
  // Create IntentMessage wrapper
  const intentMessage = {
    intent: INTENT_SCOPE,
    timestamp_ms: timestampMs, // u64 can be number, string, or bigint
    data: payload,
  };
  
  // BCS serialize the IntentMessage using the proper API
  const messageBytes = IntentMessagePriceUpdate.serialize(intentMessage).toBytes();
  
  // Hash with SHA256
  const hash = createHash('sha256').update(messageBytes).digest();
  
  // Sign with secp256k1
  const signature = sign(hash, privateKey);
  
  // Return hex-encoded compact signature (64 bytes: r + s)
  return Buffer.from(signature).toString('hex');
}

/**
 * Load secp256k1 signing key from file
 */
function loadSigningKeyFromFile(path) {
  const keyBytes = fs.readFileSync(path);
  
  // secp256k1 private key is 32 bytes
  if (keyBytes.length !== 32) {
    throw new Error(`Expected 32-byte secp256k1 private key, got ${keyBytes.length} bytes`);
  }
  
  // Verify it's a valid secp256k1 private key
  try {
    getPublicKey(keyBytes);
  } catch (error) {
    throw new Error('Invalid secp256k1 private key');
  }
  
  return keyBytes;
}

/**
 * Express route handlers
 */
const app = express();

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Get public key endpoint
app.get('/public-key', (req, res) => {
  // Derive compressed public key from private key
  const publicKey = getPublicKey(signingKey, true);
  const pkHex = Buffer.from(publicKey).toString('hex');
  
  res.json({
    public_key: pkHex,
  });
});

// Get signed price endpoint
app.get('/price', async (req, res) => {
  try {
    // Fetch current SUI price from CoinGecko
    const priceUsd = await fetchSuiPrice();
    
    // Convert to u64 with 6 decimal places precision
    const price = Math.floor(priceUsd * 1_000_000);
    
    // Get timestamp in milliseconds
    const timestampMs = currentTimestampMs();
    
    console.log(`Fetched SUI price: $${priceUsd.toFixed(6)} (raw: ${price})`);
    
    // Sign the data
    const signature = signPriceData(signingKey, price, timestampMs);
    
    res.json({
      price,
      timestamp_ms: timestampMs,
      signature,
    });
  } catch (error) {
    console.error('Failed to process price request:', error);
    res.status(503).json({
      error: 'Failed to fetch or sign price',
      message: error.message,
    });
  }
});

/**
 * Main function
 */
async function main() {
  // Get key path from command line args
  const args = process.argv.slice(2);
  if (args.length !== 1) {
    console.error('Usage: node src/index.js <path-to-signing-key>');
    process.exit(1);
  }
  const keyPath = args[0];
  
  console.log(`Loading secp256k1 signing key from: ${keyPath}`);
  signingKey = loadSigningKeyFromFile(keyPath);
  console.log('Signing key loaded successfully');
  
  // Log public key for reference
  const publicKey = getPublicKey(signingKey, true);
  console.log(`Public key (hex): ${Buffer.from(publicKey).toString('hex')}`);
  
  // Start server
  const port = 3000;
  const host = '0.0.0.0';
  
  app.listen(port, host, () => {
    console.log(`Starting server on ${host}:${port}`);
  });
}

// Run the server
main().catch((error) => {
  console.error('Fatal error:', error);
  process.exit(1);
});
