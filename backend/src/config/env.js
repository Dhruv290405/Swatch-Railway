import logger from '../logger/index.js';

const REQUIRED_ENV_VARS = [
  'JWT_SECRET'
];

const OPTIONAL_ENV_VARS = [
  'PORT', 'NODE_ENV', 'JWT_EXPIRES_IN',
  'RESEND_API_KEY', 'SENDGRID_API_KEY',
  'TWOF_API_KEY', 'TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'TWILIO_PHONE_NUMBER',
  'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION',
  'FIREBASE_STORAGE_BUCKET', 'MAX_FILE_SIZE',
  'REPORTING_FROM_EMAIL', 'AUTH_EMAIL',
  'LOG_LEVEL'
];

export function validateEnvironment() {
  const missing = REQUIRED_ENV_VARS.filter(key => !process.env[key]);
  if (!process.env.FIREBASE_SERVICE_ACCOUNT && !process.env.FIREBASE_SERVICE_ACCOUNT_BASE64) {
    missing.push('FIREBASE_SERVICE_ACCOUNT or FIREBASE_SERVICE_ACCOUNT_BASE64');
  }

  if (missing.length > 0) {
    logger.error('Environment', `Missing required environment variables: ${missing.join(', ')}`);
    if (process.env.NODE_ENV === 'production') {
      process.exit(1);
    } else {
      logger.warn('Environment', 'Running in development mode with missing env vars - some features may not work');
    }
  }
}
