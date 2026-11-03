import { reportService } from '../services/reportService.js';
import { asyncHandler } from '../middleware/errorHandler.js';

export const generate = asyncHandler(async (req, res) => {
  const result = await reportService.generateReport(req.user, req.body);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${result.filename}"`);
  res.send(result.pdfBuffer);
});

export const list = asyncHandler(async (req, res) => {
  const result = await reportService.getReports(req.user, req.query);
  res.status(200).json(result);
});

export const getById = asyncHandler(async (req, res) => {
  const result = await reportService.getReportById(req.params.reportId);
  res.status(200).json(result);
});

export const remove = asyncHandler(async (req, res) => {
  await reportService.deleteReport(req.params.reportId);
  res.status(200).json({ message: 'Report deleted successfully' });
});

export const export_report = asyncHandler(async (req, res) => {
  const result = await reportService.exportReport(req.params.reportId, req.query.format);
  res.redirect(result);
});

export const generateReport = generate;

export const emailReport = asyncHandler(async (req, res) => {
  const result = await reportService.emailReport(req.user, req.body);
  res.json(result);
});

export const getReportHistory = asyncHandler(async (req, res) => {
  const result = await reportService.getReportHistory(req.query);
  res.json(result);
});

export const getEmailHistory = asyncHandler(async (req, res) => {
  const result = await reportService.getEmailHistory(req.query);
  res.json(result);
});

export const generateAuditReport = asyncHandler(async (req, res) => {
  const { data, pdfBuffer, format } = await reportService.generateAuditReport(req.user, req.body);

  if (format === 'excel') {
    const { default: ExcelJS } = await import('exceljs');
    const wb = new ExcelJS.Workbook();
    wb.creator = 'OBHS System';
    const ws = wb.addWorksheet('Summary');
    ws.columns = [
      { header: 'Metric', key: 'metric', width: 30 },
      { header: 'Value', key: 'value', width: 30 }
    ];
    if (data?.kpi?.metrics) {
      data.kpi.metrics.forEach(m => ws.addRow({ metric: m.metric, value: m.value }));
    }
    const excelBuffer = await wb.xlsx.writeBuffer();
    res.setHeader('Content-Type', 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    res.setHeader('Content-Disposition', `attachment; filename="${data?.meta?.reportId || 'audit'}.xlsx"`);
    return res.send(excelBuffer);
  }

  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${data?.meta?.reportId || 'audit'}.pdf"`);
  res.send(pdfBuffer);
});

export const sendEmail = asyncHandler(async (req, res) => {
  const result = await reportService.sendEmail(req.user, req.body);
  res.json(result);
});

export const generateDailyReport = asyncHandler(async (req, res) => {
  const result = await reportService.generateDailyReport(req.user, req.body);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${result.filename}"`);
  res.send(result.pdfBuffer);
});

export const generateWeeklyReport = asyncHandler(async (req, res) => {
  const result = await reportService.generateWeeklyReport(req.user, req.body);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${result.filename}"`);
  res.send(result.pdfBuffer);
});

export const generateMonthlyReport = asyncHandler(async (req, res) => {
  const result = await reportService.generateMonthlyReport(req.user, req.body);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${result.filename}"`);
  res.send(result.pdfBuffer);
});

export const getCoachData = asyncHandler(async (req, res) => {
  const result = await reportService.getCoachData(req.user, req.query);
  res.json(result);
});

export const getPremisesData = asyncHandler(async (req, res) => {
  const result = await reportService.getPremisesData(req.user, req.query);
  res.json(result);
});

export const getCtsData = asyncHandler(async (req, res) => {
  const result = await reportService.getCtsData(req.user, req.query);
  res.json(result);
});

export const getCtsStats = asyncHandler(async (req, res) => {
  const result = await reportService.getCtsStats(req.user, req.query);
  res.json(result);
});

export const getCoachStats = asyncHandler(async (req, res) => {
  const result = await reportService.getCoachStats(req.user, req.query);
  res.json(result);
});

export const getPremisesStats = asyncHandler(async (req, res) => {
  const result = await reportService.getPremisesStats(req.user, req.query);
  res.json(result);
});

export const getTrainPerformance = asyncHandler(async (req, res) => {
  const result = await reportService.getTrainPerformance(req.user, req.query);
  res.json(result);
});

export const getInvoicePdf = asyncHandler(async (req, res) => {
  const result = await reportService.getInvoicePdf(req.params.uid, req.user);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${result.filename}"`);
  res.send(result.pdfBuffer);
});
