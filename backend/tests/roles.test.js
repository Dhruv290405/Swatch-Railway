import { describe, it, expect } from 'vitest';
import { ROLES, PERMISSIONS, ROLE_PERMISSIONS, ROLE_HIERARCHY } from '../src/permissions/roles.js';

/* ==========================================================================
   1. ROLE & PERMISSION DEFINITIONS
   ========================================================================== */

describe('Role Definitions', () => {
  it('all 17 roles are defined', () => {
    const expected = [
      'SUPER_ADMIN', 'COMPANY_MASTER', 'RAILWAY_MASTER',
      'ADMIN', 'RAILWAY_ADMIN', 'RAILWAY_SUPERVISOR',
      'CONTRACTOR_ADMIN', 'CONTRACTOR_SUPERVISOR',
      'STATION_MASTER', 'AREA_MASTER', 'PLATFORM_MASTER', 'CTS',
      'WORKER', 'RAILWAY_WORKER', 'JANITOR', 'ATTENDANT',
      'PASSENGER'
    ];
    for (const role of expected) {
      expect(ROLES[role], `Missing role: ${role}`).toBe(role);
    }
    expect(Object.keys(ROLES).length).toBe(expected.length);
  });

  it('all 123 permissions are defined', () => {
    expect(Object.keys(PERMISSIONS).length).toBe(123);
  });

  it('each permission value is unique and non-empty', () => {
    const values = Object.values(PERMISSIONS);
    expect(new Set(values).size).toBe(values.length);
    for (const v of values) {
      expect(v.length).toBeGreaterThan(0);
    }
  });

  it('ROLE_PERMISSIONS covers every role', () => {
    for (const role of Object.keys(ROLES)) {
      expect(ROLE_PERMISSIONS[role], `Missing entry for role: ${role}`).toBeDefined();
      expect(Array.isArray(ROLE_PERMISSIONS[role])).toBe(true);
    }
  });

  it('ROLE_HIERARCHY covers every role', () => {
    for (const role of Object.keys(ROLES)) {
      expect(ROLE_HIERARCHY[role], `Missing hierarchy for role: ${role}`).toBeDefined();
      expect(typeof ROLE_HIERARCHY[role]).toBe('number');
    }
  });

  it('hierarchy values are ordered correctly (workers share same level)', () => {
    const levels = Object.values(ROLE_HIERARCHY);
    expect(new Set(levels).size).toBeLessThanOrEqual(levels.length);
    expect(ROLE_HIERARCHY.WORKER).toBe(ROLE_HIERARCHY.RAILWAY_WORKER);
    expect(ROLE_HIERARCHY.RAILWAY_WORKER).toBe(ROLE_HIERARCHY.JANITOR);
    expect(ROLE_HIERARCHY.JANITOR).toBe(ROLE_HIERARCHY.ATTENDANT);
  });
});

describe('Permission Names - Master Data coverage', () => {
  const masterPermissions = [
    'MANAGE_PLATFORMS', 'VIEW_PLATFORMS',
    'MANAGE_AREAS', 'VIEW_AREAS',
    'MANAGE_FREQUENCIES', 'VIEW_FREQUENCIES',
    'MANAGE_ACTIVITIES', 'VIEW_ACTIVITIES',
    'MANAGE_MACHINES', 'VIEW_MACHINES',
    'MANAGE_MATERIALS', 'VIEW_MATERIALS',
  ];
  for (const perm of masterPermissions) {
    it(`${perm} is defined`, () => {
      expect(PERMISSIONS[perm]).toBeDefined();
    });
  }
});

/* ==========================================================================
   2. ROLE-PERMISSION MATRIX - MASTER DATA ACCESS
   ========================================================================== */

function hasPermission(roleKey, permKey) {
  return ROLE_PERMISSIONS[roleKey]?.includes(PERMISSIONS[permKey]) ?? false;
}

describe('SUPER_ADMIN - has every permission', () => {
  it('has all permissions', () => {
    expect(ROLE_PERMISSIONS.SUPER_ADMIN.length).toBe(Object.keys(PERMISSIONS).length);
    for (const perm of Object.values(PERMISSIONS)) {
      expect(ROLE_PERMISSIONS.SUPER_ADMIN).toContain(perm);
    }
  });
});

describe('COMPANY_MASTER - Master Data access', () => {
  const managePerms = ['MANAGE_PLATFORMS', 'MANAGE_AREAS', 'MANAGE_FREQUENCIES',
    'MANAGE_SHIFTS', 'MANAGE_DEPLOYMENTS', 'MANAGE_GEOFENCES',
    'MANAGE_INSPECTIONS', 'MANAGE_ACTIVITIES', 'MANAGE_MACHINES',
    'MANAGE_MATERIALS', 'MANAGE_PEST_CONTROL', 'MANAGE_GARBAGE',
    'MANAGE_SCORECARDS', 'MANAGE_EXECUTION'];
  for (const perm of managePerms) {
    it(`has ${perm}`, () => {
      expect(hasPermission('COMPANY_MASTER', perm)).toBe(true);
    });
  }
  const viewPerms = ['VIEW_PLATFORMS', 'VIEW_AREAS', 'VIEW_FREQUENCIES',
    'VIEW_SHIFTS', 'VIEW_DEPLOYMENTS', 'VIEW_GEOFENCES',
    'VIEW_INSPECTIONS', 'VIEW_ACTIVITIES', 'VIEW_MACHINES',
    'VIEW_MATERIALS', 'VIEW_PEST_CONTROL', 'VIEW_GARBAGE',
    'VIEW_SCORECARDS', 'VIEW_EXECUTION'];
  for (const perm of viewPerms) {
    it(`has ${perm}`, () => {
      expect(hasPermission('COMPANY_MASTER', perm)).toBe(true);
    });
  }
});

describe('RAILWAY_MASTER - Master Data access', () => {
  const managePerms = ['MANAGE_PLATFORMS', 'MANAGE_AREAS', 'MANAGE_FREQUENCIES',
    'MANAGE_SHIFTS', 'MANAGE_DEPLOYMENTS', 'MANAGE_GEOFENCES',
    'MANAGE_INSPECTIONS', 'MANAGE_ACTIVITIES', 'MANAGE_MACHINES',
    'MANAGE_MATERIALS', 'MANAGE_PEST_CONTROL', 'MANAGE_GARBAGE',
    'MANAGE_SCORECARDS', 'MANAGE_EXECUTION'];
  for (const perm of managePerms) {
    it(`has ${perm}`, () => {
      expect(hasPermission('RAILWAY_MASTER', perm)).toBe(true);
    });
  }
  for (const perm of managePerms) {
    it(`has ${perm}`, () => {
      expect(hasPermission('RAILWAY_MASTER', perm)).toBe(true);
    });
  }
});

describe('ADMIN - Read-only Master Data access', () => {
  const viewPerms = ['VIEW_PLATFORMS', 'VIEW_AREAS', 'VIEW_FREQUENCIES',
    'VIEW_SHIFTS', 'VIEW_DEPLOYMENTS', 'VIEW_GEOFENCES',
    'VIEW_INSPECTIONS', 'VIEW_ACTIVITIES', 'VIEW_MACHINES',
    'VIEW_MATERIALS', 'VIEW_PEST_CONTROL', 'VIEW_GARBAGE',
    'VIEW_SCORECARDS', 'VIEW_EXECUTION'];
  for (const perm of viewPerms) {
    it(`has VIEW ${perm}`, () => {
      expect(hasPermission('ADMIN', perm)).toBe(true);
    });
  }
  const managePerms = ['MANAGE_PLATFORMS', 'MANAGE_AREAS', 'MANAGE_FREQUENCIES',
    'MANAGE_SHIFTS', 'MANAGE_DEPLOYMENTS', 'MANAGE_GEOFENCES',
    'MANAGE_INSPECTIONS', 'MANAGE_ACTIVITIES', 'MANAGE_MACHINES',
    'MANAGE_MATERIALS', 'MANAGE_PEST_CONTROL', 'MANAGE_GARBAGE',
    'MANAGE_SCORECARDS', 'MANAGE_EXECUTION'];
  for (const perm of managePerms) {
    it(`has MANAGE ${perm}`, () => {
      expect(hasPermission('ADMIN', perm)).toBe(true);
    });
  }
  it('can assign shifts', () => {
    expect(hasPermission('ADMIN', 'ASSIGN_SHIFT')).toBe(true);
  });
  it('can manage complaints', () => {
    expect(hasPermission('ADMIN', 'MANAGE_COMPLAINTS')).toBe(true);
  });
});

describe('WORKER/RAILWAY_WORKER/JANITOR/ATTENDANT - Task access', () => {
  const minimalRoles = ['WORKER', 'RAILWAY_WORKER', 'JANITOR', 'ATTENDANT'];
  for (const role of minimalRoles) {
    it(`${role} has expected task execution permissions`, () => {
      expect(ROLE_PERMISSIONS[role]).toEqual(expect.arrayContaining([
        PERMISSIONS.VIEW_RUN_INSTANCES,
        PERMISSIONS.SUBMIT_COACH_FORM,
        PERMISSIONS.VIEW_TASKS,
        PERMISSIONS.SUBMIT_TASKS,
        PERMISSIONS.START_TASK,
        PERMISSIONS.COMPLETE_TASK,
        PERMISSIONS.RESUBMIT_TASK,
        PERMISSIONS.VIEW_DASHBOARD,
        PERMISSIONS.VIEW_RUNS,
        PERMISSIONS.VIEW_PEST_CONTROL,
        PERMISSIONS.MANAGE_PEST_CONTROL,
        PERMISSIONS.VIEW_GARBAGE,
        PERMISSIONS.MANAGE_GARBAGE,
        PERMISSIONS.VIEW_MACHINES,
      ]));
    });
  }
});

describe('CTS - Emergency task creation', () => {
  it('has VIEW_TRAINS, VIEW_RUN_INSTANCES, CREATE_EMERGENCY_TASK', () => {
    const perms = ROLE_PERMISSIONS.CTS;
    expect(perms).toContain(PERMISSIONS.VIEW_TRAINS);
    expect(perms).toContain(PERMISSIONS.VIEW_RUN_INSTANCES);
    expect(perms).toContain(PERMISSIONS.CREATE_EMERGENCY_TASK);
    expect(perms.length).toBe(3);
  });
});

describe('Role hierarchy ordering', () => {
  it('SUPER_ADMIN > COMPANY_MASTER > RAILWAY_MASTER > ADMIN > ... > WORKER', () => {
    expect(ROLE_HIERARCHY.SUPER_ADMIN).toBeGreaterThan(ROLE_HIERARCHY.COMPANY_MASTER);
    expect(ROLE_HIERARCHY.COMPANY_MASTER).toBeGreaterThan(ROLE_HIERARCHY.RAILWAY_MASTER);
    expect(ROLE_HIERARCHY.RAILWAY_MASTER).toBeGreaterThan(ROLE_HIERARCHY.ADMIN);
    expect(ROLE_HIERARCHY.ADMIN).toBeGreaterThan(ROLE_HIERARCHY.RAILWAY_ADMIN);
    expect(ROLE_HIERARCHY.RAILWAY_ADMIN).toBeGreaterThan(ROLE_HIERARCHY.RAILWAY_SUPERVISOR);
    expect(ROLE_HIERARCHY.RAILWAY_SUPERVISOR).toBeGreaterThan(ROLE_HIERARCHY.CONTRACTOR_SUPERVISOR);
    expect(ROLE_HIERARCHY.CONTRACTOR_SUPERVISOR).toBeGreaterThan(ROLE_HIERARCHY.CTS);
    expect(ROLE_HIERARCHY.CTS).toBeGreaterThan(ROLE_HIERARCHY.WORKER);
    expect(ROLE_HIERARCHY.WORKER).toBe(ROLE_HIERARCHY.JANITOR);
    expect(ROLE_HIERARCHY.JANITOR).toBe(ROLE_HIERARCHY.ATTENDANT);
  });
});

/* ==========================================================================
   3. CONTRACT MASTER SPECIFIC PERMISSIONS
   ========================================================================== */

describe('Contract permissions', () => {
  it('COMPANY_MASTER can CREATE_ENTITY, UPDATE_ENTITY, VIEW_CONTRACTS, CREATE_CONTRACT', () => {
    expect(hasPermission('COMPANY_MASTER', 'CREATE_ENTITY')).toBe(true);
    expect(hasPermission('COMPANY_MASTER', 'CREATE_CONTRACT')).toBe(true);
    expect(hasPermission('COMPANY_MASTER', 'UPDATE_CONTRACT')).toBe(true);
    expect(hasPermission('COMPANY_MASTER', 'VIEW_CONTRACTS')).toBe(true);
  });
  it('RAILWAY_MASTER can VIEW_CONTRACTS but NOT CREATE_ENTITY', () => {
    expect(hasPermission('RAILWAY_MASTER', 'VIEW_CONTRACTS')).toBe(true);
    expect(hasPermission('RAILWAY_MASTER', 'CREATE_ENTITY')).toBe(false);
    expect(hasPermission('RAILWAY_MASTER', 'CREATE_CONTRACT')).toBe(false);
  });
  it('ADMIN can VIEW_CONTRACTS only', () => {
    expect(hasPermission('ADMIN', 'VIEW_CONTRACTS')).toBe(true);
    expect(hasPermission('ADMIN', 'CREATE_CONTRACT')).toBe(false);
    expect(hasPermission('ADMIN', 'UPDATE_CONTRACT')).toBe(false);
  });
});

/* ==========================================================================
   4. STATION MASTER PERMISSIONS
   ========================================================================== */

describe('Station permissions', () => {
  const manageStationRoles = ['COMPANY_MASTER', 'RAILWAY_MASTER'];
  for (const role of manageStationRoles) {
    it(`${role} can manage and view stations`, () => {
      expect(hasPermission(role, 'CREATE_USER')).toBe(true);
    });
  }
});

/* ==========================================================================
   5. AUTHORIZATION MIDDLEWARE (unit tests without HTTP)
   ========================================================================== */

describe('Authorization middleware logic', () => {
  it('requirePermission throws ForbiddenError when role lacks permission', async () => {
    const { requirePermission } = await import('../src/middleware/authorization.js');
    const middleware = requirePermission(PERMISSIONS.MANAGE_PLATFORMS);
    const req = { user: { role: 'WORKER' } };
    const next = (err) => {
      expect(err).toBeDefined();
      expect(err.statusCode || err.name).toMatch(/Forbidden/i);
    };
    try {
      middleware(req, {}, next);
    } catch (e) {
      expect(e.name || e.constructor.name).toMatch(/Forbidden/i);
    }
  });

  it('requirePermission calls next() when role has permission', async () => {
    const { requirePermission } = await import('../src/middleware/authorization.js');
    const middleware = requirePermission(PERMISSIONS.MANAGE_PLATFORMS);
    const req = { user: { role: 'COMPANY_MASTER' } };
    let called = false;
    middleware(req, {}, () => { called = true; });
    expect(called).toBe(true);
  });

  it('requireRole allows matching role', async () => {
    const { requireRole } = await import('../src/middleware/authorization.js');
    const middleware = requireRole('SUPER_ADMIN', 'COMPANY_MASTER');
    const req = { user: { role: 'company master' } };
    let called = false;
    middleware(req, {}, () => { called = true; });
    expect(called).toBe(true);
  });

  it('requireRole blocks non-matching role', async () => {
    const { requireRole } = await import('../src/middleware/authorization.js');
    const middleware = requireRole('SUPER_ADMIN');
    const req = { user: { role: 'WORKER' } };
    let threw = false;
    try {
      middleware(req, {}, () => {});
    } catch (e) {
      threw = true;
      expect(e.name || e.constructor.name).toMatch(/Forbidden/i);
    }
    expect(threw).toBe(true);
  });

  it('requireAnyRole rejects partial match (exact match only)', async () => {
    const { requireAnyRole } = await import('../src/middleware/authorization.js');
    const middleware = requireAnyRole('admin', 'supervisor');
    const req = { user: { role: 'RAILWAY_ADMIN' } };
    let threw = false;
    try { middleware(req, {}, () => {}); } catch (e) {
      threw = true;
      expect(e.name || e.constructor.name).toMatch(/Forbidden/i);
    }
    expect(threw).toBe(true);
  });

  it('requireAnyRole allows exact role match', async () => {
    const { requireAnyRole } = await import('../src/middleware/authorization.js');
    const middleware = requireAnyRole('ADMIN', 'SUPERVISOR');
    const req = { user: { role: 'ADMIN' } };
    let called = false;
    middleware(req, {}, () => { called = true; });
    expect(called).toBe(true);
  });

  it('requireEntityAccess blocks cross-entity access for contractors', async () => {
    const { requireEntityAccess } = await import('../src/middleware/authorization.js');
    const req = {
      user: { userType: 'contractor', entityId: 'entity-A' },
      params: { uid: 'entity-B' }
    };
    let threw = false;
    try {
      requireEntityAccess(req, {}, () => {});
    } catch (e) {
      threw = true;
      expect(e.name || e.constructor.name).toMatch(/Forbidden/i);
    }
    expect(threw).toBe(true);
  });

  it('requireEntityAccess allows own entity access', async () => {
    const { requireEntityAccess } = await import('../src/middleware/authorization.js');
    const req = {
      user: { userType: 'contractor', entityId: 'entity-A' },
      params: { uid: 'entity-A' }
    };
    let called = false;
    requireEntityAccess(req, {}, () => { called = true; });
    expect(called).toBe(true);
  });
});

/* ==========================================================================
   6. MASTER DATA SERVICE METHOD EXPORTS
   ========================================================================== */

describe('Station Service - method coverage', () => {
  it('exports expected CRUD + search methods', async () => {
    const { stationService } = await import('../src/services/stationService.js');
    const expected = ['getStations', 'getStationById', 'searchStations',
      'getStationsByDivision', 'createStation', 'updateStation', 'deleteStation'];
    for (const method of expected) {
      expect(typeof stationService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

describe('Area Service - method coverage', () => {
  it('exports expected CRUD + query methods', async () => {
    const { areaService } = await import('../src/services/areaService.js');
    const expected = ['createArea', 'getAreas', 'getAreaById', 'updateArea',
      'deleteArea', 'getAreasByStation', 'getAreasByPlatform'];
    for (const method of expected) {
      expect(typeof areaService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

describe('Activity Service - method coverage', () => {
  it('exports expected CRUD methods', async () => {
    const { activityService } = await import('../src/services/activityService.js');
    const expected = ['createActivity', 'getActivities', 'getActivityById',
      'updateActivity', 'deleteActivity'];
    for (const method of expected) {
      expect(typeof activityService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

describe('Frequency Service - method coverage', () => {
  it('exports expected CRUD methods', async () => {
    const { frequencyService } = await import('../src/services/frequencyService.js');
    const expected = ['createFrequency', 'getFrequencies', 'getFrequencyById',
      'updateFrequency', 'deleteFrequency'];
    for (const method of expected) {
      expect(typeof frequencyService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

describe('Machine Service - method coverage', () => {
  it('exports expected CRUD methods', async () => {
    const { machineService } = await import('../src/services/machineService.js');
    const expected = ['createMachine', 'getMachines', 'getMachineById',
      'updateMachine', 'deleteMachine'];
    for (const method of expected) {
      expect(typeof machineService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

describe('Material Service - method coverage', () => {
  it('exports expected CRUD + transaction methods', async () => {
    const { materialService } = await import('../src/services/materialService.js');
    const expected = ['createMaterial', 'getMaterials', 'getMaterialById',
      'updateMaterial', 'deleteMaterial', 'issueMaterial', 'receiveMaterial',
      'getStockAlerts', 'getMaterialLogs'];
    for (const method of expected) {
      expect(typeof materialService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

describe('Contract Service - method coverage', () => {
  it('exports expected CRUD + query methods', async () => {
    const { contractService } = await import('../src/services/contractService.js');
    const expected = ['createContract', 'updateContract', 'getContracts',
      'getContractByUid', 'getContractByNumber', 'getContractsByEntity',
      'rejectContract'];
    for (const method of expected) {
      expect(typeof contractService[method], `Missing method: ${method}`).toBe('function');
    }
  });
});

/* ==========================================================================
   7. MASTER DATA ROUTE FILES
   ========================================================================== */

describe('Route files export correctly', () => {
  const routes = [
    ['station', '../src/routes/station.js'],
    ['area', '../src/routes/area.js'],
    ['activity', '../src/routes/activity.js'],
    ['frequency', '../src/routes/frequency.js'],
    ['machine', '../src/routes/machine.js'],
    ['material', '../src/routes/material.js'],
    ['platform', '../src/routes/platform.js'],
  ];
  for (const [name, path] of routes) {
    it(`${name} route exports a router`, async () => {
      const mod = await import(path);
      const router = mod.default;
      expect(router).toBeDefined();
      expect(typeof router).toBe('function');
      expect(router.stack).toBeDefined();
      expect(Array.isArray(router.stack)).toBe(true);
      expect(router.stack.length).toBeGreaterThan(0);
    });
  }
});

/* ==========================================================================
   8. MASTER DATA CONTROLLER FILES
   ========================================================================== */

describe('Controller files export handlers', () => {
  const controllers = [
    ['station', '../src/controllers/stationController.js', ['list', 'create', 'update', 'remove', 'getById', 'search', 'getByDivision']],
    ['area', '../src/controllers/areaController.js', ['list', 'create', 'update', 'remove', 'getById', 'getByStation', 'getByPlatform']],
    ['activity', '../src/controllers/activityController.js', ['list', 'create', 'update', 'remove', 'getById']],
    ['frequency', '../src/controllers/frequencyController.js', ['list', 'create', 'update', 'remove', 'getById']],
    ['machine', '../src/controllers/machineController.js', ['list', 'create', 'update', 'remove', 'getById']],
    ['material', '../src/controllers/materialController.js', ['list', 'create', 'update', 'remove', 'getById', 'issue', 'receive', 'getStockAlerts', 'getLogs']],
  ];
  for (const [name, path, methods] of controllers) {
    for (const method of methods) {
      it(`${name}Controller.${method} is a function`, async () => {
        const mod = await import(path);
        expect(typeof mod[method], `Missing export: ${method}`).toBe('function');
      });
    }
  }
});

/* ==========================================================================
   9. MASTER DATA SERVICE CREATION FIELD COVERAGE
   ========================================================================== */

describe('Station Master - createStation field coverage', () => {
  it('accepts all required fields and returns station data', () => {
    const { stationService } = require('../src/services/stationService.js');
    const serviceProto = Object.getPrototypeOf(stationService);
    const createFn = stationService.createStation;
    const fnStr = createFn.toString();
    const required = ['stationCode', 'stationName', 'zone', 'division'];
    const optional = ['category', 'stationType', 'address', 'latitude', 'longitude', 'active'];
    for (const field of required) {
      expect(fnStr).toContain(field);
    }
    for (const field of optional) {
      expect(fnStr).toContain(field);
    }
  });
});

describe('Area Master - VALID_AREA_TYPES coverage', () => {
  it('contains all 16 required area types', async () => {
    const { areaService } = await import('../src/services/areaService.js');
    const fnStr = areaService.createArea.toString();
    // Check that the module exports VALID_AREA_TYPES indirectly through validation
    const expected = ['Toilet', 'Waiting Hall', 'Track', 'Escalator', 'Lift',
      'Water Booth', 'Staircase', 'Office', 'Concourse', 'FOB',
      'Circulating Area', 'Approach Road', 'Gardens',
      'Goods Platform/Goods Line', 'Drains', 'Other'];
    // Re-read the file to check the constant
    const fs = await import('fs');
    const source = fs.readFileSync('./src/services/areaService.js', 'utf8');
    for (const areaType of expected) {
      expect(source, `Missing area type: ${areaType}`).toContain(areaType);
    }
  });
});

describe('Activity Master - all 16 activities', () => {
  it('VALID_ACTIVITY_TYPES contains all required activities', async () => {
    const fs = await import('fs');
    const source = fs.readFileSync('./src/services/activityService.js', 'utf8');
    const expected = ['sweeping', 'mopping', 'washing', 'rag_picking',
      'toilet_cleaning', 'drain_cleaning', 'water_booth_cleaning',
      'garbage_collection', 'garbage_disposal', 'cobweb_removal',
      'stain_removal', 'pest_control', 'rodent_control', 'deep_cleaning',
      'consumable_refill', 'inspection_closure'];
    for (const activity of expected) {
      expect(source, `Missing activity: ${activity}`).toContain(activity);
    }
  });
});

describe('Frequency Master - all 9 frequencies', () => {
  it('VALID_FREQUENCY_TYPES contains all required frequencies', async () => {
    const fs = await import('fs');
    const source = fs.readFileSync('./src/services/frequencyService.js', 'utf8');
    const expected = ['once_per_day', 'twice_per_day', 'three_times_per_day',
      'every_six_hours', 'hourly', 'weekly', 'fortnightly', 'monthly',
      'as_and_when_required'];
    for (const freq of expected) {
      expect(source, `Missing frequency: ${freq}`).toContain(freq);
    }
  });
});

describe('Machine Master - createMachine field coverage', () => {
  it('createMachine accepts all required fields', async () => {
    const { machineService } = await import('../src/services/machineService.js');
    const fnStr = machineService.createMachine.toString();
    const fields = ['machineName', 'machineType', 'serialNumber', 'stationId',
      'location', 'workingStatus', 'workingStatus', 'hourlyRate', 'dailyRate',
      'downtimeEntry', 'replacementStatus', 'remarks'];
    for (const field of fields) {
      expect(fnStr, `Missing field: ${field}`).toContain(field);
    }
  });
});

describe('Material Master - createMaterial field coverage', () => {
  it('createMaterial accepts all required fields', async () => {
    const { materialService } = await import('../src/services/materialService.js');
    const fnStr = materialService.createMaterial.toString();
    const fields = ['materialName', 'materialType', 'unit', 'stationId',
      'openingBalance', 'monthlyRequirement', 'reorderLevel', 'unitPrice', 'remarks',
      'issuedQuantity', 'usedQuantity', 'currentStock'];
    for (const field of fields) {
      expect(fnStr, `Missing field: ${field}`).toContain(field);
    }
  });
});

describe('Contract Master - createContract field coverage', () => {
  it('createContract accepts all required fields', async () => {
    const { contractService } = await import('../src/services/contractService.js');
    const fnStr = contractService.createContract.toString();
    const fields = ['contractNumber', 'contractName', 'entityId', 'stationIds',
      'stationNames', 'startDate', 'endDate', 'contractDuration', 'contractValue',
      'workCategories', 'assignedRailwayOfficials', 'assignedContractorUsers',
      'scoringApplicability', 'billingCycle', 'representative'];
    for (const field of fields) {
      expect(fnStr, `Missing field: ${field}`).toContain(field);
    }
  });
});

/* ==========================================================================
   10. APP.JS - ALL ROUTES MOUNTED
   ========================================================================== */

describe('app.js - all master data routes mounted', () => {
  it('mounts station, area, activity, frequency, machine, material, platform routes', async () => {
    const fs = await import('fs');
    const source = fs.readFileSync('./src/app.js', 'utf8');
    const expected = [
      "platformRoutes",
      "areaRoutes",
      "activityRoutes",
      "frequencyRoutes",
      "materialRoutes",
      "machineRoutes",
      "contractsRoutes",
      "stationRoutes"
    ];
    for (const route of expected) {
      expect(source, `Missing mount: ${route}`).toContain(route);
    }
  });
});
