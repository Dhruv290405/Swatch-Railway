import dotenv from 'dotenv';
dotenv.config();

function parseFirebaseServiceAccount(rawValue) {
  if (!rawValue) return null;

  let raw = rawValue.trim();
  if ((raw.startsWith("'") && raw.endsWith("'")) || (raw.startsWith('"') && raw.endsWith('"'))) {
    raw = raw.slice(1, -1);
  }

  let serviceAccount;
  try {
    serviceAccount = JSON.parse(raw);
  } catch (error) {
    throw new Error(`FIREBASE_SERVICE_ACCOUNT must contain valid JSON: ${error.message}`);
  }

  if (!serviceAccount || typeof serviceAccount !== 'object' || !serviceAccount.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is missing private_key');
  }

  // Render can preserve a second level of escaping when JSON is pasted into
  // an environment variable. Firebase Admin requires real newline characters.
  serviceAccount.private_key = serviceAccount.private_key.replace(/\\n/g, '\n');
  if (!serviceAccount.private_key.includes('BEGIN PRIVATE KEY') ||
      !serviceAccount.private_key.includes('END PRIVATE KEY')) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT contains an invalid private_key');
  }
  return serviceAccount;
}

function readFirebaseServiceAccount() {
  const encodedValue = process.env.FIREBASE_SERVICE_ACCOUNT_BASE64;
  if (encodedValue) {
    const normalizedValue = encodedValue.trim();
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(normalizedValue) || normalizedValue.length % 4 !== 0) {
      throw new Error('FIREBASE_SERVICE_ACCOUNT_BASE64 is not valid base64');
    }

    let decodedValue;
    try {
      decodedValue = Buffer.from(normalizedValue, 'base64').toString('utf8');
    } catch (error) {
      throw new Error(`FIREBASE_SERVICE_ACCOUNT_BASE64 is invalid: ${error.message}`);
    }
    return parseFirebaseServiceAccount(decodedValue);
  }

  return parseFirebaseServiceAccount(process.env.FIREBASE_SERVICE_ACCOUNT);
}

const config = Object.freeze({
  port: parseInt(process.env.PORT, 10) || 5000,
  nodeEnv: process.env.NODE_ENV || 'development',
  jwtSecret: process.env.JWT_SECRET || (() => {
    if (process.env.NODE_ENV === 'production') {
      throw new Error('JWT_SECRET environment variable is required');
    }
    return 'dev-secret-do-not-use-in-production';
  })(),
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '7d',
  jwtOtpExpiresIn: '15d',

  firebase: {
    serviceAccount: readFirebaseServiceAccount(),
    storageBucket: process.env.FIREBASE_STORAGE_BUCKET || 'swachh-railways.firebasestorage.app'
  },

  resend: {
    apiKey: process.env.RESEND_API_KEY
  },

  sms: {
    twoFactorApiKey: process.env.TWOF_API_KEY || process.env.TWO_FACTOR_API_KEY || process.env.TWOFACTOR_API_KEY || process.env['2FACTOR_API_KEY'],
    twilio: {
      accountSid: process.env.TWILIO_ACCOUNT_SID,
      authToken: process.env.TWILIO_AUTH_TOKEN,
      phoneNumber: process.env.TWILIO_PHONE_NUMBER
    }
  },

  sendgrid: {
    apiKey: process.env.SENDGRID_API_KEY
  },

  aws: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    region: process.env.AWS_REGION || 'ap-south-1'
  },

  upload: {
    maxFileSize: parseInt(process.env.MAX_FILE_SIZE, 10) || 5 * 1024 * 1024,
    allowedMimeTypes: ['image/jpeg', 'image/png', 'image/webp', 'image/gif']
  },

  imageProcessing: {
    thumbnailWidth: 200,
    thumbnailHeight: 200,
    maxWidth: 1920,
    maxHeight: 1080,
    quality: 80,
    thumbnailQuality: 60
  },

  archive: {
    evidenceDaysOld: 7,
    longTermDaysOld: 30,
    batchSize: 100
  },

  pagination: {
    defaultLimit: 50,
    maxLimit: 200
  },

  rateLimit: {
    windowMs: 15 * 60 * 1000,
    max: 100
  },

  otp: {
    expiryMs: 300000,
    maxAttempts: 5
  },

  reporting: {
    fromEmail: process.env.REPORTING_FROM_EMAIL || 'Swachh Railways <reports@swachhrailways.com>',
    authEmail: process.env.AUTH_EMAIL || 'Swachh Railways <auth@swachhrailways.com>'
  }
});

export default config;
