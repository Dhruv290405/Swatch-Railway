import { ForbiddenError } from '../errors/index.js';
import { ROLE_PERMISSIONS } from '../permissions/roles.js';

export function requirePermission(permission) {
  return (req, res, next) => {
    const role = (req.user?.role || '').toUpperCase();
    const normalizedRole = role.replace(/\s+/g, '_');
    const permissions = ROLE_PERMISSIONS[normalizedRole] || [];

    if (!permissions.includes(permission)) {
      console.log(`[AuthZ] Failed permission ${permission} for role "${role}" (normalized: "${normalizedRole}"). Permissions:`, permissions);
      throw new ForbiddenError(`Insufficient permissions. Required: ${permission}`);
    }
    next();
  };
}

export function requireAnyPermission(...permissions) {
  return (req, res, next) => {
    const role = (req.user?.role || '').toUpperCase();
    const normalizedRole = role.replace(/\s+/g, '_');
    const rolePermissions = ROLE_PERMISSIONS[normalizedRole] || [];

    const allowed = permissions.filter((p) => rolePermissions.includes(p));
    if (allowed.length === 0) {
      console.log(`[AuthZ] Failed any-of ${permissions.join(', ')} for role "${role}" (normalized: "${normalizedRole}"). Permissions:`, rolePermissions);
      throw new ForbiddenError(`Insufficient permissions. Required one of: ${permissions.join(', ')}`);
    }
    next();
  };
}

export function requireRole(...allowedRoles) {
  return (req, res, next) => {
    const userRole = (req.user?.role || '').toUpperCase();
    const normalizedUserRole = userRole.replace(/\s+/g, '_');

    const allowed = allowedRoles.map(r => r.toUpperCase().replace(/\s+/g, '_'));

    if (!allowed.includes(normalizedUserRole)) {
      throw new ForbiddenError(`Access denied. Required role: ${allowedRoles.join(' or ')}`);
    }
    next();
  };
}

export function requireAnyRole(...allowedRoles) {
  return (req, res, next) => {
    const userRole = (req.user?.role || '').toUpperCase().replace(/\s+/g, '_');
    const allowed = allowedRoles.map(r => r.toUpperCase().replace(/\s+/g, '_'));

    if (!allowed.includes(userRole)) {
      throw new ForbiddenError(`Access denied. Requires one of: ${allowedRoles.join(', ')}`);
    }
    next();
  };
}

export function requireEntityAccess(req, res, next) {
  const { userType, entityId: userEntityId } = req.user || {};
  const targetEntityId = req.params.uid || req.query.entityId || req.body.entityId;

  if (userType === 'contractor' && targetEntityId && targetEntityId !== userEntityId) {
    throw new ForbiddenError('You can only access your own company data');
  }
  next();
}

export function requireStationAccess(req, res, next) {
  const stationId = req.user?.stationId;
  const userStations = req.user?.stations;
  if (stationId || (userStations && userStations.length > 0)) {
    const targetStationId = req.params.stationId || req.body.stationId || req.query.stationId;
    if (targetStationId) {
      const allowed = [stationId, ...(userStations || [])].filter(Boolean);
      if (!allowed.includes(targetStationId)) {
        throw new ForbiddenError('You can only access your assigned station');
      }
    }
  }
  next();
}

export function requirePlatformAccess(req, res, next) {
  const platformId = req.user?.platformId || req.user?.areaId;
  if (platformId) {
    const targetPlatformId = req.params.platformId || req.body.platformId || req.query.platformId;
    if (targetPlatformId && targetPlatformId !== platformId) {
      throw new ForbiddenError('You can only access your assigned platform');
    }
  }
  next();
}

export function requireAreaAccess(req, res, next) {
  const role = (req.user?.role || '').toUpperCase();
  next();
}

export function requireContractType(...allowedTypes) {
  return (req, res, next) => {
    const userContractType = req.user?.contractType;
    if (userContractType && !allowedTypes.includes(userContractType)) {
      throw new ForbiddenError(`Access denied. Requires contract type: ${allowedTypes.join(' or ')}`);
    }
    next();
  };
}

export function forbidContractType(...forbiddenTypes) {
  return (req, res, next) => {
    const userContractType = req.user?.contractType;
    if (userContractType && forbiddenTypes.includes(userContractType)) {
      throw new ForbiddenError(`Access denied. Users with contract type "${userContractType}" cannot access this resource.`);
    }
    next();
  };
}

export function requireMasterAccess(minRole) {
  return (req, res, next) => {
    const role = (req.user?.role || '').toUpperCase();
    const roleHierarchy = {
      'SUPER_ADMIN': 100,
      'COMPANY_MASTER': 90,
      'RAILWAY_MASTER': 80,
      'ADMIN': 70,
      'RAILWAY_ADMIN': 60,
      'RAILWAY_INSPECTOR': 52,
      'RAILWAY_SUPERVISOR': 50,
      'CONTRACTOR_ADMIN': 45,
      'CONTRACTOR_SUPERVISOR': 40,
      'CTS': 30,
      'WORKER': 10,
      'RAILWAY_WORKER': 10,
      'JANITOR': 10,
      'ATTENDANT': 10,
      'PASSENGER': 1
    };

    const userRoleLevel = roleHierarchy[role] || 0;
    const requiredRoleLevel = roleHierarchy[minRole] || 0;

    if (userRoleLevel < requiredRoleLevel) {
      throw new ForbiddenError(`Access denied. Requires ${minRole} or higher role`);
    }
    next();
  };
}

export function requireZoneMasterAccess(req, res, next) {
  const role = (req.user?.role || '').toUpperCase();
  if (!['SUPER_ADMIN', 'ADMIN', 'RAILWAY_MASTER', 'RAILWAY_ADMIN', 'COMPANY_MASTER'].includes(role)) {
    throw new ForbiddenError('Access denied. Requires zone master or higher role');
  }
  next();
}

export function requireDashboardLevelAccess(level) {
  return (req, res, next) => {
    const role = (req.user?.role || '').toUpperCase().replace(/\s+/g, '_');
    const roleHierarchy = {
      'SUPER_ADMIN': 100, 'COMPANY_MASTER': 90, 'RAILWAY_MASTER': 80,
      'ADMIN': 70, 'RAILWAY_ADMIN': 60,
      'RAILWAY_INSPECTOR': 52,
      'RAILWAY_SUPERVISOR': 50, 'CONTRACTOR_ADMIN': 45,
      'CONTRACTOR_SUPERVISOR': 40, 'CTS': 30,
      'WORKER': 10, 'RAILWAY_WORKER': 10, 'JANITOR': 10, 'ATTENDANT': 10, 'PASSENGER': 1
    };

    const userRoleLevel = roleHierarchy[role] || 0;

    switch (level) {
      case 'admin':
        if (userRoleLevel < 60 && role !== 'COMPANY_MASTER') {
          throw new ForbiddenError('Admin dashboard access requires admin privileges');
        }
        break;
      case 'zone':
        if (userRoleLevel < 48) {
          throw new ForbiddenError('Zone dashboard access requires zone-level privileges');
        }
        break;
      case 'station':
        if (userRoleLevel < 48) {
          throw new ForbiddenError('Station dashboard access requires station-level privileges');
        }
        break;
      case 'platform':
        if (userRoleLevel < 35) {
          throw new ForbiddenError('Platform dashboard access requires platform-level privileges');
        }
        break;
      case 'area':
        if (userRoleLevel < 35) {
          throw new ForbiddenError('Area dashboard access requires area-level privileges');
        }
        break;
    }
    next();
  };
}
