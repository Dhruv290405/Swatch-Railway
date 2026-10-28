import { asyncHandler } from '../middleware/errorHandler.js';

// Base allowed items per role. Super Admin gets everything.
const ROLE_ALLOWED = {
  'Super Admin': { screens: ['home','contracts','tasks','entities','profile','dashboard'], tabs: ['home','contracts','tasks','entities','profile'], quickActions: ['createContract','manageEntity'] },
};

const DEFAULT_ALLOWED = { screens: ['home','tasks','profile'], tabs: ['home','tasks','profile'], quickActions: [] };

const LABELS = {
  nav: { home:'Home', contracts:'Contracts', tasks:'Tasks', entities:'Entities', profile:'Profile', dashboard:'Dashboard' },
  buttons: { createContract:'Create Contract', manageEntity:'Manage Entity', save:'Save', cancel:'Cancel' },
  messages: { noData:'No data available', loading:'Loading...' },
};

export const getUiConfig = asyncHandler(async (req, res) => {
  const role = req.user?.role || null;
  const allowed = (role && ROLE_ALLOWED[role]) || DEFAULT_ALLOWED;
  res.status(200).json({
    success: true,
    role: role,
    allowedScreens: allowed.screens,
    allowedTabs: allowed.tabs,
    allowedQuickActions: allowed.quickActions,
    labels: LABELS,
    featureFlags: { entityManagement: true, contractEntityDropdown: true },
  });
});

export default { getUiConfig };
