import { AppError } from '../errors/AppError.js';
import logger from '../logger/index.js';

export function errorHandler(err, req, res, _next) {
  logger.error('ErrorHandler', 'Received error', {
    message: err?.message,
    code: err?.code,
    name: err?.name,
    statusCode: err?.statusCode,
    type: typeof err,
    stack: err?.stack?.split('\n').slice(0, 3).join('\n')
  });

  // Layer 1: AppError and its subclasses (ValidationError, AuthenticationError, ForbiddenError, NotFoundError)
  if (err instanceof AppError) {
    logger.error('ErrorHandler', 'Handled as AppError', { message: err.message, code: err.code, statusCode: err.statusCode });
    return res.status(err.statusCode).json({
      success: false,
      error: err.message,
      code: err.code,
      ...(err.details && { details: err.details })
    });
  }

  // Layer 1.5: Handle gRPC/Google Cloud errors (e.g., Firestore quota exceeded - code 8)
  const isGRPCError = err && typeof err === 'object' && (err.code !== undefined || err.details !== undefined);
  if (isGRPCError) {
    const grpcCode = err.code;
    if (grpcCode === 8 || grpcCode === 'RESOURCE_EXHAUSTED') {
      logger.error('ErrorHandler', 'Firestore quota exceeded', { message: err.message, code: grpcCode });
      return res.status(503).json({
        success: false,
        error: 'Service temporarily unavailable. Database quota exceeded.',
        code: 'QUOTA_EXCEEDED'
      });
    }
    // Other gRPC errors
    logger.error('ErrorHandler', 'gRPC error', { message: err.message, code: grpcCode, details: err.details });
    return res.status(500).json({
      success: false,
      error: process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message,
      code: 'GRPC_ERROR'
    });
  }

  // Layer 2: Handle Error objects (has message and stack)
  if (err instanceof Error) {
    const errorMessage = process.env.NODE_ENV === 'production' ? 'Internal server error' : err.message;
    const errorCode = process.env.NODE_ENV === 'production' ? 'INTERNAL_ERROR' : (err.code || 'INTERNAL_ERROR');
    logger.error('ErrorHandler', 'Handled as Error object', { message: err.message, code: errorCode });
    return res.status(500).json({
      success: false,
      error: errorMessage,
      code: errorCode
    });
  }

  // Layer 3: Handle string errors
  if (typeof err === 'string') {
    const errorMessage = process.env.NODE_ENV === 'production' ? 'Internal server error' : err;
    const errorCode = process.env.NODE_ENV === 'production' ? 'INTERNAL_ERROR' : 'INTERNAL_ERROR';
    logger.error('ErrorHandler', 'Handled as string error', { message: err, code: errorCode });
    return res.status(500).json({
      success: false,
      error: errorMessage,
      code: errorCode
    });
  }

  // Layer 4: Handle number errors (gRPC status codes, etc.)
  if (typeof err === 'number') {
    const errorMessage = process.env.NODE_ENV === 'production' ? 'Internal server error' : String(err);
    const errorCode = process.env.NODE_ENV === 'production' ? 'INTERNAL_ERROR' : 'INTERNAL_ERROR';
    logger.error('ErrorHandler', 'Handled as number error', { message: String(err), code: errorCode });
    return res.status(500).json({
      success: false,
      error: errorMessage,
      code: errorCode
    });
  }

  // Layer 5: Fallback for anything else
  logger.error('ErrorHandler', 'Unhandled error type', { error: err });
  return res.status(500).json({
    success: false,
    error: process.env.NODE_ENV === 'production' ? 'Internal server error' : 'Unknown error',
    code: 'INTERNAL_ERROR'
  });
}

/**
 * Wraps an async route/middleware handler so that any thrown errors
 * are forwarded to Express's next(err) error handler automatically.
 * @param {Function} fn - async Express middleware/handler
 */
export function asyncHandler(fn) {
  return (req, res, next) => {
    Promise.resolve(fn(req, res, next)).catch(next);
  };
}

export { AppError, ValidationError, AuthenticationError, TokenError, ForbiddenError, NotFoundError, ConflictError, RateLimitError, FirestoreError, IndexError } from '../errors/AppError.js';

/**
 * 404 handler for unknown routes
 */
export function notFoundHandler(req, res, _next) {
  logger.warn('NotFoundHandler', 'Route not found', { 
    method: req.method, 
    url: req.originalUrl,
    ip: req.ip 
  });
  return res.status(404).json({
    success: false,
    error: 'Route not found',
    code: 'NOT_FOUND'
  });
}