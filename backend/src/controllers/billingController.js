import { billingService } from '../services/billingService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const createConfig = asyncHandler(async (req, res) => {
  const result = await billingService.saveBillingConfig(req.body, req.user);
  res.status(201).json(result);
});

export const listConfig = asyncHandler(async (req, res) => {
  const result = await billingService.listBillingConfigs(req.user);
  res.status(200).json(result);
});

export const getConfigByContract = asyncHandler(async (req, res) => {
  const result = await billingService.getBillingConfigByContract(req.params.contractId);
  res.status(200).json(result);
});

export const generateReport = asyncHandler(async (req, res) => {
  const result = await billingService.createInvoice(req.user, req.body);
  res.status(201).json(result);
});

// Generates the monthly bill for every billable contract. With month + year it targets that month;
// without them it fills in every completed month that has no bill yet.
export const generateMonthly = asyncHandler(async (req, res) => {
  const { month, year } = req.body || {};
  const result = (month && year)
    ? await billingService.generateMonthlyBills({ month, year, user: req.user })
    : await billingService.ensureMonthlyBills(req.user, { monthsBack: Number(req.body?.monthsBack) || 12 });
  res.status(201).json(result);
});

export const listReports = asyncHandler(async (req, res) => {
  const result = await billingService.getInvoices({ user: req.user, ...req.query });
  res.status(200).json(result);
});

export const getReportById = asyncHandler(async (req, res) => {
  const result = await billingService.getInvoiceById(req.params.uid);
  res.status(200).json(result);
});

export const approveReport = asyncHandler(async (req, res) => {
  const result = await billingService.approveBill(req.params.uid, req.user);
  res.status(200).json(result);
});

export const rejectReport = asyncHandler(async (req, res) => {
  const result = await billingService.rejectBill(req.params.uid, req.body, req.user);
  res.status(200).json(result);
});

export const dashboard = asyncHandler(async (req, res) => {
  const result = await billingService.getDashboard(req.user);
  res.status(200).json(result);
});

export const generateInvoice = asyncHandler(async (req, res) => {
  const result = await billingService.generateInvoiceNumber(req.params.uid, req.user);
  res.status(200).json(result);
});

export const contractorReports = asyncHandler(async (req, res) => {
  const result = await billingService.getContractorDashboard(req.user);
  res.status(200).json(result);
});

export const supervisorReports = asyncHandler(async (req, res) => {
  const result = await billingService.getSupervisorDashboard(req.user);
  res.status(200).json(result);
});

export const getInvoicePdf = asyncHandler(async (req, res) => {
  const filePath = await billingService.getInvoicePdf(req.params.uid);
  res.download(filePath);
});
