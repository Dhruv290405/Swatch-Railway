import jwt from 'jsonwebtoken';
import { db } from '../database/index.js';
import config from '../config/index.js';
import { asyncHandler } from './errorHandler.js';

export const verifyToken = asyncHandler(async (req, res, next) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) {
    return res.status(401).json({ error: 'No token provided.' });
  }

  const decoded = jwt.verify(token, config.jwtSecret);
  const userDoc = await db.collection('users').doc(decoded.uid).get();

  if (!userDoc.exists) {
    return res.status(401).json({ error: 'User no longer exists.' });
  }

  const userData = userDoc.data();

  let entityDetails = null;
  if (userData.entityId) {
    const entityDoc = await db.collection('entities').doc(userData.entityId).get();
    if (entityDoc.exists) {
      entityDetails = entityDoc.data();
    }
  }

  let contractDetails = null;
  if (userData.contractId) {
    const contractDoc = await db.collection('contracts').doc(userData.contractId).get();
    if (contractDoc.exists) {
      contractDetails = contractDoc.data();
    }
  }

  req.user = {
    uid: decoded.uid,
    email: decoded.email,
    role: decoded.role,
    fullName: userData.fullName,
    name: userData.fullName,
    zone: userData.zone,
    division: userData.division,
    depot: userData.depot,
    stationId: userData.stationId || null,
    platformId: userData.platformId || null,
    areaId: userData.areaId || null,
    userType: userData.userType,
    entityId: userData.entityId,
    entityName: entityDetails?.companyName || null,
    entityDetails: entityDetails,
    contractId: userData.contractId || null,
    contractType: userData.contractType || null,
    workerType: userData.worker_type || userData.workerType || null,
    stations: userData.stations || [],
    domain: userData.domain || null
  };

  next();
});
