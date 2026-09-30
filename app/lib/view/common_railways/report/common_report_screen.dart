import 'dart:io';
import 'dart:typed_data';
import 'package:crm_train/services/api_services.dart';
import 'package:crm_train/services/dashboard_counts_service.dart';
import 'package:crm_train/repositories/obhs_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import '../../../providers/auth_provider.dart';
import '../../../utills/app_colors.dart';
import '../widgets/rolevise_dropdowns.dart';
import '../report_excel_format/obhs_report_excel.dart';
import '../station_management/area_performance_dashboard.dart';
import '../../../services/pdf_report_service.dart';
import '../../../repositories/worker_repo.dart';
import 'package:printing/printing.dart';
class CommonReportScreen extends StatefulWidget {
  final int initialIndex;
  const CommonReportScreen({super.key, this.initialIndex = 0});

  @override
  State<CommonReportScreen> createState() => _CommonReportScreenState();
}

class _CommonReportScreenState extends State<CommonReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool _isPremisesFilterExpanded = true;
  bool _isCoachFilterExpanded = true;
  bool _isCTSFilterExpanded = true;
  bool _isOBHSFilterExpanded = true;


  final List<String> ares = [
    'GICC',
    'NWS',
    'OWS',
    'Platform',
    'PuneYard',
    'Hadapsar',
    'Khadki',
  ];

  List<String> selectedContractors = [];
  List<String> selectedAres = [];
  String? selectedSupervisor;
  String selectedRoleFilter = 'All Contractor';
  String? trainNo;
  String? coachNo;
  String? areaName;
  String? premisesName;
  DateTime? startDate;
  DateTime? endDate;
  List<dynamic> premisesReportData = [];
  List<dynamic> coachReportData = [];
  List<dynamic> ctsReportData = [];
  List<dynamic> obhsReportData = [];
  bool premisesReportGenerated = false;
  bool coachReportGenerated = false;
  bool ctsReportGenerated = false;
  bool obhsReportGenerated = false;
  bool isLoading = false;
  bool isDownloading = false;

  String? selectedOBHSTrain;
  int? selectedOBHSInstance;
  String? selectedOBHSCoach;
  bool includeCompleteTrainData = false;

  String? _selectedFilterZone;
  String? _selectedFilterDivision;
  String? _selectedFilterDepot;

  Map<String, dynamic> premisesStats = {};
  Map<String, dynamic> coachStats = {};
  Map<String, dynamic> ctsStats = {};
  Map<String, dynamic> obhsStats = {};
  bool isLoadingStats = true;

  String? selectedReportType;
  DateTime? selectedDepartureDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: widget.initialIndex < 3 ? widget.initialIndex : 0);
    _loadStatistics();
  }

  Future<void> _loadStatistics() async {
    final user = Provider.of<AuthProvider>(context, listen: false).currentUser;
    if (user == null) return;

    setState(() => isLoadingStats = true);

    try {
      final premisesData = await FirebaseCountService.getPremisesCleaningStats(
        userRole: user.role,
        uid: user.uid,
        zone: user.zone,
        division: user.division,
        depot: user.depot,
        entityId: user.entityId,
        contractId: user.contractId,
      );

      final coachData = await FirebaseCountService.getCoachCleaningStats(
        userRole: user.role,
        uid: user.uid,
        zone: user.zone,
        division: user.division,
        depot: user.depot,
        entityId: user.entityId,
        contractId: user.contractId,
      );

      final ctsData = await ApiService.getCTSStatistics(
        userRole: user.role,
        uid: user.uid,
        zone: user.zone,
        division: user.division,
        depot: user.depot,
      );

      setState(() {
        premisesStats = premisesData;
        coachStats = coachData;
        ctsStats = ctsData;
        isLoadingStats = false;
      });
    } catch (e) {
      debugPrint("Error loading statistics: $e");
      setState(() => isLoadingStats = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked != null) {
      setState(() {
        startDate = picked.start;
        endDate = picked.end;
      });
    }
  }

  Future<void> _generatePremisesReport() async {
    final provider = Provider.of<AuthProvider>(context, listen: false);
    final user = provider.currentUser;
    if (startDate == null || endDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select date range")));
      return;
    }

    if (selectedAres.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please select area")));
      return;
    }

    setState(() => isLoading = true);

    try {
      final formattedStart = DateFormat('yyyy-MM-dd').format(startDate!);
      final formattedEnd = DateFormat('yyyy-MM-dd').format(endDate!);

      final zoneToSend = _selectedFilterZone ?? user?.zone ?? "";
      final divisionToSend = _selectedFilterDivision ?? user?.division ?? '';
      final depotToSend = _selectedFilterDepot ?? user?.depot ?? '';

      final areasToSend = selectedAres.join(',');

      final response = await ApiService.getPremisesReportData(
        startDate: formattedStart,
        endDate: formattedEnd,
        areaType: areasToSend,
        zone: zoneToSend,
        division: divisionToSend,
        depot: depotToSend,
        contractId: '',
        contractorId: '',
      );

      final dataList = response['data'] as List<dynamic>? ?? [];

      setState(() {
        premisesReportData = dataList;
        premisesReportGenerated = dataList.isNotEmpty;
        isLoading = false;
      });

      if (dataList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No data found for selected criteria")),
        );
        return;
      }

      _showReportGeneratedDialog(true);
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showReportGeneratedDialog(bool isPremises) {
    final data = isPremises ? premisesReportData : coachReportData;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Success", style: TextStyle(color: Colors.green)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Report Generated Successfully!"),
            SizedBox(height: 8),
            Text(
              "${data.length} record found",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Close"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(Icons.file_download, color: Colors.white, size: 18),
            label: Text(
              "Download Excel",
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (isPremises) {
                _downloadPremisesExcel();
              } else {
                _downloadCoachExcel();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPremisesExcel() async {
    if (premisesReportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No data available to download")),
      );
      return;
    }

    setState(() => isDownloading = true);

    try {
      final workbook = xlsio.Workbook();

      Map<String, List<dynamic>> groupedData = {};
      for (var item in premisesReportData) {
        final premiseName = item["premiseName"]?.toString() ?? "Unknown";
        if (!groupedData.containsKey(premiseName)) {
          groupedData[premiseName] = [];
        }
        groupedData[premiseName]!.add(item);
      }

      int sheetIndex = 0;
      for (var entry in groupedData.entries) {
        final premiseName = entry.key;
        final premiseData = entry.value;

        xlsio.Worksheet sheet;
        if (sheetIndex == 0) {
          sheet = workbook.worksheets[0];
          sheet.name = premiseName.length > 31
              ? premiseName.substring(0, 31)
              : premiseName;
        } else {
          sheet = workbook.worksheets.add();
          sheet.name = premiseName.length > 31
              ? premiseName.substring(0, 31)
              : premiseName;
        }

        final headerStyle = workbook.styles.add('headerStyle$sheetIndex')
          ..backColor = '#1F4E78'
          ..fontColor = '#FFFFFF'
          ..bold = true
          ..hAlign = xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center
          ..wrapText = true
          ..borders.all.lineStyle = xlsio.LineStyle.thin;

        final subHeaderStyle = workbook.styles.add('subHeaderStyle$sheetIndex')
          ..backColor = '#4472C4'
          ..fontColor = '#FFFFFF'
          ..bold = true
          ..hAlign = xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center
          ..borders.all.lineStyle = xlsio.LineStyle.thin;

        final cellStyle = workbook.styles.add('cellStyle$sheetIndex')
          ..hAlign = xlsio.HAlignType.center
          ..vAlign = xlsio.VAlignType.center
          ..borders.all.lineStyle = xlsio.LineStyle.thin;

        sheet.getRangeByName('A1').setText('Date');
        sheet.getRangeByName('B1').setText('Premise Name');
        sheet.getRangeByName('C1').setText('Total Area in Sq Mtrs');
        sheet.getRangeByName('D1').setText('Area attended for Cleaning');
        sheet.getRangeByName('E1').setText('Area Not Attended / Not Cleaned');
        sheet
            .getRangeByName('F1')
            .setText('Rating of Cleaning on the Day in %');
        sheet.getRangeByName('G1').setText('Housekeeping Score');
        sheet.getRangeByName('H1').setText('Pit-Line Score');
        sheet.getRangeByName('I1').setText('Garbage Score');
        sheet.getRangeByName('J1').setText('Overall Score');
        sheet.getRangeByName('K1').setText('90%+');

        sheet.getRangeByName('L1:N1').merge();
        sheet
            .getRangeByName('L1')
            .setText('Penalty for Cleaning having rating');
        sheet.getRangeByName('L2').setText('81% to 90%');
        sheet.getRangeByName('M2').setText('71% to 80%');
        sheet.getRangeByName('N2').setText('70% and below');

        sheet.getRangeByName('A1:K1').cellStyle = headerStyle;
        sheet.getRangeByName('L1').cellStyle = headerStyle;
        sheet.getRangeByName('L2:N2').cellStyle = subHeaderStyle;

        sheet.getRangeByName('A1').columnWidth = 15;
        sheet.getRangeByName('B1').columnWidth = 20;
        sheet.getRangeByName('C1').columnWidth = 20;
        sheet.getRangeByName('D1').columnWidth = 22;
        sheet.getRangeByName('E1').columnWidth = 25;
        sheet.getRangeByName('F1').columnWidth = 25;
        sheet.getRangeByName('G1').columnWidth = 20;
        sheet.getRangeByName('H1').columnWidth = 20;
        sheet.getRangeByName('I1').columnWidth = 20;
        sheet.getRangeByName('J1').columnWidth = 20;
        sheet.getRangeByName('K1').columnWidth = 12;

        for (int i = 12; i <= 14; i++) {
          sheet.getRangeByIndex(1, i).columnWidth = 15;
        }

        int rowIndex = 3;

        for (var item in premiseData) {
          final totalArea =
              item["totalAreaSqMeters"]?.toString() ??
              item["totalArea"]?.toString() ??
              "0";
          final areaAttended =
              item["areaAttendedForCleaning"]?.toString() ??
              item["totalAreaSqMeters"]?.toString() ??
              item["totalArea"]?.toString() ??
              "0";

          sheet
              .getRangeByIndex(rowIndex, 1)
              .setText(item["date"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 2)
              .setText(item["premiseName"]?.toString() ?? "");
          sheet.getRangeByIndex(rowIndex, 3).setText(totalArea);
          sheet.getRangeByIndex(rowIndex, 4).setText(areaAttended);
          sheet
              .getRangeByIndex(rowIndex, 5)
              .setText("0"); // Area not attended = 0
          sheet
              .getRangeByIndex(rowIndex, 6)
              .setText(item["ratingInPct"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 7)
              .setText(item["housekeepingScore"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 8)
              .setText(item["pitLineScore"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 9)
              .setText(item["garbageScore"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 10)
              .setText(item["overallScore"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 11)
              .setText(item["above90"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 12)
              .setText(item["penalty81to90"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 13)
              .setText(item["penalty71to80"]?.toString() ?? "");
          sheet
              .getRangeByIndex(rowIndex, 14)
              .setText(item["penaltyBelow70"]?.toString() ?? "");

          sheet.getRangeByName('A$rowIndex:N$rowIndex').cellStyle = cellStyle;
          sheet.getRangeByName('A$rowIndex:N$rowIndex').rowHeight = 25;

          rowIndex++;
        }

        sheetIndex++;
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/Premises_Cleaning_Report_$timestamp.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      setState(() => isDownloading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Report downloaded with ${groupedData.length} sheets!"),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: "Open",
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(file.path),
          ),
        ),
      );

      await OpenFilex.open(file.path);
    } catch (e) {
      setState(() => isDownloading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Download failed: $e")));
    }
  }

  Future<void> _downloadCoachExcel() async {
    if (coachReportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No data available to download")),
      );
      return;
    }

    setState(() => isDownloading = true);

    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];

      final yellowHeader = workbook.styles.add('yellowHeader')
        ..backColor = '#FFFFFF'
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      final purpleHeader = workbook.styles.add('purpleHeader')
        ..backColor = '#9966CC'
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      final lightBlueHeader = workbook.styles.add('lightBlueHeader')
        ..backColor = '#ADD8E6'
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      final whiteHeader = workbook.styles.add('whiteHeader')
        ..backColor = '#FFFFFF'
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      final dataStyle = workbook.styles.add('dataStyle')
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      sheet.getRangeByName('A1:A3').merge();
      sheet.getRangeByName('A1').setText('Date');
      sheet.getRangeByName('A1').cellStyle = whiteHeader;

      sheet.getRangeByName('B1:B3').merge();
      sheet.getRangeByName('B1').setText('Train');
      sheet.getRangeByName('B1').cellStyle = whiteHeader;

      sheet.getRangeByName('C1:C3').merge();
      sheet
          .getRangeByName('C1')
          .setText(
            'TYPE OF WORK\n(PRIMARY/\nSECONDARY/ RBPC WITH\nM/C / RBPC\nWITHOUT M/C',
          );
      sheet.getRangeByName('C1').cellStyle = whiteHeader;

      sheet.getRangeByName('D1:D3').merge();
      sheet.getRangeByName('D1').setText('WITH OR\nWITHOUT\nACWP');
      sheet.getRangeByName('D1').cellStyle = whiteHeader;

      sheet.getRangeByName('E1:H1').merge();
      sheet.getRangeByName('E1').setText('Internal Cleaning');
      sheet.getRangeByName('E1').cellStyle = yellowHeader;
      sheet.getRangeByName('E2:H2').merge();
      sheet.getRangeByName('E2').setText('Primary or Secondary');
      sheet.getRangeByName('E2').cellStyle = yellowHeader;

      sheet.getRangeByName('I1:L1').merge();
      sheet.getRangeByName('I1').setText('Internal Cleaning');
      sheet.getRangeByName('I1').cellStyle = yellowHeader;
      sheet.getRangeByName('I2:L2').merge();
      sheet.getRangeByName('I2').setText('RBPC With Machine');
      sheet.getRangeByName('I2').cellStyle = yellowHeader;

      sheet.getRangeByName('M1:P1').merge();
      sheet.getRangeByName('M1').setText('Internal Cleaning');
      sheet.getRangeByName('M1').cellStyle = yellowHeader;
      sheet.getRangeByName('M2:P2').merge();
      sheet.getRangeByName('M2').setText('RBPC Without Machine');
      sheet.getRangeByName('M2').cellStyle = yellowHeader;

      sheet.getRangeByName('Q1:T1').merge();
      sheet.getRangeByName('Q1').setText('Intensive Cleaning');
      sheet.getRangeByName('Q1').cellStyle = yellowHeader;
      sheet.getRangeByName('Q2:T2').merge();
      sheet.getRangeByName('Q2').setText('Without ACWP');
      sheet.getRangeByName('Q2').cellStyle = yellowHeader;

      sheet.getRangeByName('U1:X1').merge();
      sheet.getRangeByName('U1').setText('External Cleaning');
      sheet.getRangeByName('U1').cellStyle = purpleHeader;
      sheet.getRangeByName('U2:X2').merge();
      sheet.getRangeByName('U2').setText('With ACWP');
      sheet.getRangeByName('U2').cellStyle = purpleHeader;

      sheet.getRangeByName('Y1:AB1').merge();
      sheet.getRangeByName('Y1').setText('External Cleaning');
      sheet.getRangeByName('Y1').cellStyle = purpleHeader;
      sheet.getRangeByName('Y2:AB2').merge();
      sheet.getRangeByName('Y2').setText('Without ACWP');
      sheet.getRangeByName('Y2').cellStyle = purpleHeader;

      sheet.getRangeByName('AC1:AE1').merge();
      sheet.getRangeByName('AC1').setText('Toiletries');
      sheet.getRangeByName('AC1').cellStyle = lightBlueHeader;

      sheet.getRangeByName('AF1:AH1').merge();
      sheet.getRangeByName('AF1').setText('Watering');
      sheet.getRangeByName('AF1').cellStyle = lightBlueHeader;

      sheet.getRangeByName('AI1:AK1').merge();
      sheet.getRangeByName('AI1').setText('Door Locking');
      sheet.getRangeByName('AI1').cellStyle = lightBlueHeader;

      sheet.getRangeByName('AL1:AL3').merge();
      sheet.getRangeByName('AL1').setText('ACTUAL MANPOWER (with ACWP)');
      sheet.getRangeByName('AL1').cellStyle = whiteHeader;

      sheet.getRangeByName('AM1:AM3').merge();
      sheet.getRangeByName('AM1').setText('ACTUAL MANPOWER (without ACWP)');
      sheet.getRangeByName('AM1').cellStyle = whiteHeader;

      sheet.getRangeByName('AN1:AN3').merge();
      sheet.getRangeByName('AN1').setText('MANPOWER SHORTAGE');
      sheet.getRangeByName('AN1').cellStyle = whiteHeader;

      sheet.getRangeByName('AO1:AO3').merge();
      sheet.getRangeByName('AO1').setText('Machine SHORTAGE');
      sheet.getRangeByName('AO1').cellStyle = whiteHeader;

      final subHeaders = ['A', 'B', 'C', 'D'];

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 5 + i).setText(subHeaders[i]);
        sheet.getRangeByIndex(3, 5 + i).cellStyle = yellowHeader;
      }

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 9 + i).setText(subHeaders[i]);
        sheet.getRangeByIndex(3, 9 + i).cellStyle = yellowHeader;
      }

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 13 + i).setText(subHeaders[i]);
        sheet.getRangeByIndex(3, 13 + i).cellStyle = yellowHeader;
      }

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 17 + i).setText(subHeaders[i]);
        sheet.getRangeByIndex(3, 17 + i).cellStyle = yellowHeader;
      }

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 21 + i).setText(subHeaders[i]);
        sheet.getRangeByIndex(3, 21 + i).cellStyle = purpleHeader;
      }
      sheet.getRangeByIndex(3, 25).setText('NA');
      sheet.getRangeByIndex(3, 25).cellStyle = purpleHeader;

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 25 + i).setText(subHeaders[i]);
        sheet.getRangeByIndex(3, 25 + i).cellStyle = purpleHeader;
      }

      final yesNoNaHeaders = ['Yes', 'No', 'NA'];

      for (int i = 0; i < 3; i++) {
        sheet.getRangeByIndex(3, 29 + i).setText(yesNoNaHeaders[i]);
        sheet.getRangeByIndex(3, 29 + i).cellStyle = lightBlueHeader;
      }

      for (int i = 0; i < 3; i++) {
        sheet.getRangeByIndex(3, 32 + i).setText(yesNoNaHeaders[i]);
        sheet.getRangeByIndex(3, 32 + i).cellStyle = lightBlueHeader;
      }

      for (int i = 0; i < 3; i++) {
        sheet.getRangeByIndex(3, 35 + i).setText(yesNoNaHeaders[i]);
        sheet.getRangeByIndex(3, 35 + i).cellStyle = lightBlueHeader;
      }

      sheet.getRangeByName('A1').columnWidth = 10;
      sheet.getRangeByName('B1').columnWidth = 30;
      sheet.getRangeByName('C1').columnWidth = 20;
      sheet.getRangeByName('D1').columnWidth = 15;

      for (int i = 5; i <= 37; i++) {
        sheet.getRangeByIndex(1, i).columnWidth = 5;
      }

      sheet.getRangeByName('AL1').columnWidth = 18;
      sheet.getRangeByName('AM1').columnWidth = 18;
      sheet.getRangeByName('AN1').columnWidth = 15;
      sheet.getRangeByName('AO1').columnWidth = 15;

      int rowIndex = 4;

      for (var item in coachReportData) {
        sheet
            .getRangeByIndex(rowIndex, 1)
            .setText(item["date"]?.toString() ?? "");

        final trainNumber = item["trainNo"]?.toString() ?? "";
        final trainName = item["trainName"]?.toString() ?? "";
        final trainDisplay = trainName.isNotEmpty
            ? "$trainNumber - $trainName"
            : trainNumber;

        sheet.getRangeByIndex(rowIndex, 2).setText(trainDisplay);
        sheet
            .getRangeByIndex(rowIndex, 3)
            .setText(item["workType"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 4)
            .setText(item["acwpStatus"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 5)
            .setText(item["int_A"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 6)
            .setText(item["int_B"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 7)
            .setText(item["int_C"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 8)
            .setText(item["int_D"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 9)
            .setText(item["rbpc_mach_A"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 10)
            .setText(item["rbpc_mach_B"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 11)
            .setText(item["rbpc_mach_C"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 12)
            .setText(item["rbpc_mach_D"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 13)
            .setText(item["rbpc_man_A"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 14)
            .setText(item["rbpc_man_B"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 15)
            .setText(item["rbpc_man_C"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 16)
            .setText(item["rbpc_man_D"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 17)
            .setText(item["intense_A"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 18)
            .setText(item["intense_B"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 19)
            .setText(item["intense_C"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 20)
            .setText(item["intense_D"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 21)
            .setText(item["ext_acwp_A"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 22)
            .setText(item["ext_acwp_B"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 23)
            .setText(item["ext_acwp_C"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 24)
            .setText(item["ext_acwp_D"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 25)
            .setText(item["ext_acwp_NA"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 26)
            .setText(item["ext_man_A"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 27)
            .setText(item["ext_man_B"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 28)
            .setText(item["ext_man_C"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 29)
            .setText(item["ext_man_D"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 29)
            .setText(item["toil_Yes"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 30)
            .setText(item["toil_No"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 31)
            .setText(item["toil_NA"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 32)
            .setText(item["water_Yes"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 33)
            .setText(item["water_No"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 34)
            .setText(item["water_NA"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 35)
            .setText(item["door_Yes"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 36)
            .setText(item["door_No"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 37)
            .setText(item["door_NA"]?.toString() ?? "");

        sheet
            .getRangeByIndex(rowIndex, 38)
            .setText(item["actualWithACWP"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 39)
            .setText(item["actualWithoutACWP"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 40)
            .setText(item["manpowerShortage"]?.toString() ?? "");
        sheet
            .getRangeByIndex(rowIndex, 41)
            .setText(item["machineShortage"]?.toString() ?? "");

        for (int col = 1; col <= 41; col++) {
          sheet.getRangeByIndex(rowIndex, col).cellStyle = dataStyle;
        }

        rowIndex++;
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/Coach_Cleaning_Report_$timestamp.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      setState(() => isDownloading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Report downloaded successfully!"),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: "Open",
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(file.path),
          ),
        ),
      );

      await OpenFilex.open(file.path);
    } catch (e) {
      setState(() => isDownloading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Download failed: $e")));
    }
  }

  Future<void> _generateCoachReport() async {
    final provider = Provider.of<AuthProvider>(context, listen: false);
    final user = provider.currentUser;

    bool hasDateRange = startDate != null && endDate != null;
    bool hasTrainNo = trainNo != null && trainNo!.isNotEmpty;
    bool hasCoachNo = coachNo != null && coachNo!.isNotEmpty;

    if (!hasDateRange && !hasTrainNo && !hasCoachNo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please provide at least one filter: Date Range, Train No, or Coach No",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final formattedStart = startDate != null
          ? DateFormat('yyyy-MM-dd').format(startDate!)
          : "";

      final formattedEnd = endDate != null
          ? DateFormat('yyyy-MM-dd').format(endDate!)
          : "";

      final zoneToSend = _selectedFilterZone ?? user?.zone ?? "";
      final divisionToSend = _selectedFilterDivision ?? user?.division ?? '';
      final depotToSend = _selectedFilterDepot ?? user?.depot ?? '';

      final response = await ApiService.getCoachReportData(
        startDate: formattedStart,
        endDate: formattedEnd,
        trainNo: trainNo ?? '',
        coachNo: coachNo ?? '',
        contractorId: selectedContractors.isNotEmpty
            ? selectedContractors.first
            : '',
        zone: zoneToSend,
        division: divisionToSend,
        depot: depotToSend,
        contractId: '',
      );

      final dataList = response['data'] as List<dynamic>? ?? [];

      setState(() {
        coachReportData = dataList;
        coachReportGenerated = dataList.isNotEmpty;
        isLoading = false;
      });

      if (dataList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No data found for selected criteria")),
        );
        return;
      }

      _showReportGeneratedDialog(false);
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _generateCTSReport() async {
    final provider = Provider.of<AuthProvider>(context, listen: false);
    final user = provider.currentUser;

    bool hasDateRange = startDate != null && endDate != null;
    bool hasTrainNo = trainNo != null && trainNo!.isNotEmpty;

    if (!hasDateRange && !hasTrainNo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Please provide at least one filter: Date Range or Train No",
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      final formattedStart = startDate != null
          ? DateFormat('yyyy-MM-dd').format(startDate!)
          : "";

      final formattedEnd = endDate != null
          ? DateFormat('yyyy-MM-dd').format(endDate!)
          : "";

      final zoneToSend = _selectedFilterZone ?? user?.zone ?? "";
      final divisionToSend = _selectedFilterDivision ?? user?.division ?? '';
      final depotToSend = _selectedFilterDepot ?? user?.depot ?? '';

      final response = await ApiService.getCTSReportData(
        startDate: formattedStart,
        endDate: formattedEnd,
        trainNo: trainNo ?? '',
        contractorId: selectedContractors.isNotEmpty
            ? selectedContractors.first
            : '',
        zone: zoneToSend,
        division: divisionToSend,
        depot: depotToSend,
        contractId: '',
      );

      final dataList = response['data'] as List<dynamic>? ?? [];

      setState(() {
        ctsReportData = dataList;
        ctsReportGenerated = dataList.isNotEmpty;
        isLoading = false;
      });

      if (dataList.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No data found for selected criteria")),
        );
        return;
      }

      _showCTSReportGeneratedDialog();
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  void _showCTSReportGeneratedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text("Success", style: TextStyle(color: Colors.green)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Report Generated Successfully!"),
            SizedBox(height: 8),
            Text(
              "${ctsReportData.length} record found",
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text("Close"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(Icons.file_download, color: Colors.white, size: 18),
            label: Text(
              "Download Excel",
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _downloadCTSExcel();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _downloadCTSExcel() async {
    if (ctsReportData.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No data available to download")),
      );
      return;
    }

    setState(() => isDownloading = true);

    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'CTS Report';

      final headerStyle = workbook.styles.add('headerStyle')
        ..bold = true
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..wrapText = true
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      final dataStyle = workbook.styles.add('dataStyle')
        ..hAlign = xlsio.HAlignType.center
        ..vAlign = xlsio.VAlignType.center
        ..borders.all.lineStyle = xlsio.LineStyle.thin;

      sheet.getRangeByName('A1').columnWidth = 12;
      sheet.getRangeByName('B1').columnWidth = 30;
      sheet.getRangeByName('C1').columnWidth = 18;
      sheet.getRangeByName('D1').columnWidth = 18;
      sheet.getRangeByName('E1').columnWidth = 16;
      sheet.getRangeByName('F1').columnWidth = 16;
      sheet.getRangeByName('G1').columnWidth = 22;
      sheet.getRangeByName('H1').columnWidth = 22;
      sheet.getRangeByName('I1').columnWidth = 12;
      sheet.getRangeByName('J1').columnWidth = 16;
      sheet.getRangeByName('K1').columnWidth = 18;
      sheet.getRangeByName('L1').columnWidth = 8;
      sheet.getRangeByName('M1').columnWidth = 16;
      sheet.getRangeByName('N1').columnWidth = 18;
      sheet.getRangeByName('O1').columnWidth = 14;
      sheet.getRangeByName('P1').columnWidth = 18;

      for (int i = 17; i <= 28; i++) {
        sheet.getRangeByIndex(1, i).columnWidth = 8;
      }

      sheet.getRangeByName('AC1').columnWidth = 18;
      sheet.getRangeByName('AD1').columnWidth = 16;
      sheet.getRangeByName('AE1').columnWidth = 14;
      sheet.getRangeByName('AF1').columnWidth = 14;
      sheet.getRangeByName('AG1').columnWidth = 20;
      sheet.getRangeByName('AH1').columnWidth = 18;

      final row1Headers = [
        'Date', 'Train No.', 'Actual Arrival Time', 'Actual Departure Time',
        'Work Start Time', 'Work End Time', 'Contractor Supervisor Name',
        'Railway Supervisor Name', 'Total Coaches', 'Attended Coaches',
        'Unattended Coaches', 'Late', 'Garbage Disposed', 'Nominated Location',
        'Machines Used', 'Chemical Used (Liter)'
      ];

      for (int i = 0; i < row1Headers.length; i++) {
        sheet.getRangeByIndex(1, i + 1).setText(row1Headers[i]);
        sheet.getRangeByIndex(1, i + 1).cellStyle = headerStyle;
      }

      sheet.getRangeByName('Q1:AB1').merge();
      sheet.getRangeByName('Q1').setText('Grade Distribution');
      sheet.getRangeByName('Q1').cellStyle = headerStyle;

      final finalRow1Headers = [
        'Sampled Coaches %', 'Sampled Coaches', 'Overall Grade',
        'Overall Score', 'Actual Manpower Used', 'Manpower Shortage'
      ];

      for (int i = 0; i < finalRow1Headers.length; i++) {
        sheet.getRangeByIndex(1, 29 + i).setText(finalRow1Headers[i]);
        sheet.getRangeByIndex(1, 29 + i).cellStyle = headerStyle;
      }

      sheet.getRangeByName('Q2:T2').merge();
      sheet.getRangeByName('Q2').setText('Jet Clean');
      sheet.getRangeByName('Q2').cellStyle = headerStyle;

      sheet.getRangeByName('U2:X2').merge();
      sheet.getRangeByName('U2').setText('Basin Clean');
      sheet.getRangeByName('U2').cellStyle = headerStyle;

      sheet.getRangeByName('Y2:AB2').merge();
      sheet.getRangeByName('Y2').setText('Disposal');
      sheet.getRangeByName('Y2').cellStyle = headerStyle;

      final gradeHeaders = ['A', 'B', 'C', 'D'];

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 17 + i).setText(gradeHeaders[i]);
        sheet.getRangeByIndex(3, 17 + i).cellStyle = headerStyle;
      }

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 21 + i).setText(gradeHeaders[i]);
        sheet.getRangeByIndex(3, 21 + i).cellStyle = headerStyle;
      }

      for (int i = 0; i < 4; i++) {
        sheet.getRangeByIndex(3, 25 + i).setText(gradeHeaders[i]);
        sheet.getRangeByIndex(3, 25 + i).cellStyle = headerStyle;
      }

      int rowIndex = 4;

      for (var item in ctsReportData) {
        sheet.getRangeByIndex(rowIndex, 1).setText(item["date"]?.toString() ?? "");

        final trainNumber = item["trainNo"]?.toString() ?? "";
        final trainName = item["trainName"]?.toString() ?? "";
        final trainDisplay = trainName.isNotEmpty ? "$trainNumber - $trainName" : trainNumber;
        sheet.getRangeByIndex(rowIndex, 2).setText(trainDisplay);

        sheet.getRangeByIndex(rowIndex, 3).setText(item["actualArrival"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 4).setText(item["actualDeparture"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 5).setText(item["workStart"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 6).setText(item["workEnd"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 7).setText(item["contractorSupervisor"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 8).setText(item["railwaySupervisor"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 9).setText(item["totalCoaches"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 10).setText(item["attendedCoaches"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 11).setText(item["unattendedCoaches"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 12).setText(item["late"]?.toString() ?? "No");
        sheet.getRangeByIndex(rowIndex, 13).setText(item["garbageDisposed"]?.toString() ?? "No");
        sheet.getRangeByIndex(rowIndex, 14).setText(item["location"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 15).setText(item["machinesUsedCount"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 16).setText(item["chemicalUsedLiter"]?.toString() ?? "");

        sheet.getRangeByIndex(rowIndex, 17).setText(item["jet_A"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 18).setText(item["jet_B"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 19).setText(item["jet_C"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 20).setText(item["jet_D"]?.toString() ?? "");

        sheet.getRangeByIndex(rowIndex, 21).setText(item["basin_A"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 22).setText(item["basin_B"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 23).setText(item["basin_C"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 24).setText(item["basin_D"]?.toString() ?? "");

        sheet.getRangeByIndex(rowIndex, 25).setText(item["disposal_A"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 26).setText(item["disposal_B"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 27).setText(item["disposal_C"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 28).setText(item["disposal_D"]?.toString() ?? "");

        sheet.getRangeByIndex(rowIndex, 29).setText(item["sampledPercentage"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 30).setText(item["sampledCoaches"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 31).setText(item["overallGrade"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 32).setText(item["overallScore"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 33).setText(item["actualManpower"]?.toString() ?? "");
        sheet.getRangeByIndex(rowIndex, 34).setText(item["manpowerShortage"]?.toString() ?? "");

        for (int col = 1; col <= 34; col++) {
          sheet.getRangeByIndex(rowIndex, col).cellStyle = dataStyle;
        }

        rowIndex++;
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/CTS_Report_$timestamp.xlsx');
      await file.writeAsBytes(bytes, flush: true);

      setState(() => isDownloading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("CTS Report downloaded with ${ctsReportData.length} record."),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: "Open",
            textColor: Colors.white,
            onPressed: () => OpenFilex.open(file.path),
          ),
        ),
      );

      await OpenFilex.open(file.path);
    } catch (e) {
      setState(() => isDownloading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Download failed: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Reports',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: kRailwayBlue,
        elevation: 0.5,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: const [
                  Tab(text: "Premises"),
                  Tab(text: "Coach"),
                  Tab(text: "CTS"),
                ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPremisesCleaningTab(),
          _buildCoachCleaningTab(),
          _buildCTSTab(),
        ],
      ),
    );
  }

  Widget _buildPremisesCleaningTab() {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [

              const SizedBox(height: 16),

              _expandableFilterContainer(
                title: "Filter Reports",
                isExpanded: _isPremisesFilterExpanded,
                onTap: () {
                  setState(() {
                    _isPremisesFilterExpanded = !_isPremisesFilterExpanded;
                  });
                },
                children: [
                  if (user != null && user.role != 'Railway Supervisor') ...[
                    ZoneDivisionDepotDropdowns(
                      user: user,
                      onChangedWithZone: (zone, division, depot) {
                        setState(() {
                          _selectedFilterZone = zone;
                          _selectedFilterDivision = division;
                          _selectedFilterDepot = depot;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  _multiSelectTile(
                    label: "Areas",
                    items: ares,
                    selected: selectedAres,
                    onTap: () async {
                      final selected = await _showMultiSelectDialog(
                        ares,
                        selectedAres,
                      );
                      if (selected != null)
                        setState(() => selectedAres = selected);
                    },
                  ),
                  const SizedBox(height: 12),
                  _dateRangePicker(),
                  const SizedBox(height: 20),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: const Icon(Icons.assessment, color: Colors.white),
                    label: const Text(
                      "Generate Report",
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                    onPressed: isLoading ? null : _generatePremisesReport,
                  ),
                ],
              ),

              const SizedBox(height: 25),

              _summaryContainer(
                title: "Comprehensive Performance Summary",
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _summaryCard(
                        title: "Total Premises Cleaned",
                        value: isLoadingStats
                            ? "..."
                            : (premisesStats['totalPremisesCleaned']
                                      ?.toString() ??
                                  "0"),
                        color: Colors.blue,
                      ),
                      _summaryCard(
                        title: "Total Area Cleaned (Sq Mtrs)",
                        value: isLoadingStats
                            ? "..."
                            : (premisesStats['totalAreaCleaned']?.toString() ??
                                  "0"),
                        color: Colors.green,
                      ),
                      _summaryCard(
                        title: "Total Area Uncleaned (Sq Mtrs)",
                        value: isLoadingStats
                            ? "..."
                            : (premisesStats['totalAreaUncleaned']
                                      ?.toString() ??
                                  "0"),
                        color: Colors.orange,
                      ),
                      _summaryCard(
                        title: "Man Power Deployed",
                        value: isLoadingStats
                            ? "..."
                            : (premisesStats['manpower']?.toString() ?? "0"),
                        color: Colors.purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Overall Grade Distribution",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kRailwayBlue),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _gradeItem(
                          grade: 'Above 90%',
                          count: isLoadingStats
                              ? '...'
                              : '${premisesStats['gradeAbove90'] ?? 0}',
                          percent: isLoadingStats
                              ? '...'
                              : '${premisesStats['gradeAbove90Pct'] ?? '0.0'}%',
                          color: Colors.green,
                        ),
                        _verticalDivider(),
                        _gradeItem(
                          grade: '81 - 90%',
                          count: isLoadingStats
                              ? '...'
                              : '${premisesStats['grade81to90'] ?? 0}',
                          percent: isLoadingStats
                              ? '...'
                              : '${premisesStats['grade81to90Pct'] ?? '0.0'}%',
                          color: Colors.blue,
                        ),
                        _verticalDivider(),
                        _gradeItem(
                          grade: '71 - 80%',
                          count: isLoadingStats
                              ? '...'
                              : '${premisesStats['grade71to80'] ?? 0}',
                          percent: isLoadingStats
                              ? '...'
                              : '${premisesStats['grade71to80Pct'] ?? '0.0'}%',
                          color: Colors.orange,
                        ),
                        _verticalDivider(),
                        _gradeItem(
                          grade: '70 & Below',
                          count: isLoadingStats
                              ? '...'
                              : '${premisesStats['gradeBelow70'] ?? 0}',
                          percent: isLoadingStats
                              ? '...'
                              : '${premisesStats['gradeBelow70Pct'] ?? '0.0'}%',
                          color: Colors.red,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (isLoading || isDownloading)
          Container(
            color: Colors.black54,
            child: Center(
              child: Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        isLoading ? "Generating Report..." : "Downloading...",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCoachCleaningTab() {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _expandableFilterContainer(
            title: "Filter Reports",
            isExpanded: _isCoachFilterExpanded,
            onTap: () {
              setState(() {
                _isCoachFilterExpanded = !_isCoachFilterExpanded;
              });
            },
            children: [
                  if (user != null)
                    ZoneDivisionDepotDropdowns(
                      user: user,
                      onChangedWithZone: (zone, division, depot) {
                        setState(() {
                          _selectedFilterZone = zone;
                          _selectedFilterDivision = division;
                          _selectedFilterDepot = depot;
                        });
                      },
                    ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _textField("Train No", (v) => trainNo = v)),
                  const SizedBox(width: 10),
                  Expanded(child: _textField("Coach No", (v) => coachNo = v)),
                ],
              ),
              const SizedBox(height: 12),
              _dateRangePicker(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.assessment, color: Colors.white),
                label: const Text(
                  "Generate Report",
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                onPressed: isLoading ? null : _generateCoachReport,
              ),
            ],
          ),

          const SizedBox(height: 25),

          _summaryContainer(
            title: "Comprehensive Performance Summary",
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  _summaryCard(
                    title: "Total Trains Scored",
                    value: isLoadingStats
                        ? "..."
                        : (coachStats['scored']?.toString() ?? "0"),
                    color: Colors.blue,
                  ),
                  _summaryCard(
                    title: "Total Coaches",
                    value: isLoadingStats
                        ? "..."
                        : (coachStats['totalCoachesCleaned']?.toString() ??
                              "0"),
                    color: Colors.orange,
                  ),
                  _summaryCard(
                    title: "Total Manpower",
                    value: isLoadingStats
                        ? "..."
                        : (coachStats['manpower']?.toString() ?? "0"),
                    color: Colors.teal,
                  ),
                  _summaryCard(
                    title: "Total Penalty",
                    value: '0',
                    color: Colors.red,
                    isMoney: true,
                  ),
                ],
              ),
              const Text(
                "Overall Grade Distribution",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kRailwayBlue),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _gradeItem(
                      grade: 'A',
                      count: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeA'] ?? 0}',
                      percent: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeAPercent'] ?? '0.0'}%',
                      color: Colors.green,
                    ),
                    _verticalDivider(),
                    _gradeItem(
                      grade: 'B',
                      count: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeB'] ?? 0}',
                      percent: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeBPercent'] ?? '0.0'}%',
                      color: Colors.blue,
                    ),
                    _verticalDivider(),
                    _gradeItem(
                      grade: 'C',
                      count: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeC'] ?? 0}',
                      percent: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeCPercent'] ?? '0.0'}%',
                      color: Colors.orange,
                    ),
                    _verticalDivider(),
                    _gradeItem(
                      grade: 'D',
                      count: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeD'] ?? 0}',
                      percent: isLoadingStats
                          ? '...'
                          : '${coachStats['gradeDPercent'] ?? '0.0'}%',
                      color: Colors.red,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                "P&C PERFORMANCE SUMMARY",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kRailwayBlue),
                  color: Colors.white,
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.5),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                    3: FlexColumnWidth(1),
                  },
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  children: [
                    // Header Row
                    TableRow(
                      decoration: BoxDecoration(
                        color: kRailwayBlue.withOpacity(0.1),
                      ),
                      children: [
                        _tableHeaderCell('Activity'),
                        _tableHeaderCell('✓'),
                        _tableHeaderCell('✗'),
                        _tableHeaderCell('N/A'),
                      ],
                    ),
                    // Toiletries Row
                    TableRow(
                      children: [
                        _tableCell('Toiletries Cleaned', isLabel: true),
                        _tableCell(
                          isLoadingStats ? '...' : '${coachStats['toiletriesYes'] ?? 0}',
                          color: Colors.green,
                        ),
                        _tableCell(
                          isLoadingStats ? '...' : '${coachStats['toiletriesNo'] ?? 0}',
                          color: Colors.red,
                        ),
                        _tableCell('0', color: Colors.grey),
                      ],
                    ),
                    // Doors Locked Row
                    TableRow(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                      ),
                      children: [
                        _tableCell('Doors Locked', isLabel: true),
                        _tableCell(
                          isLoadingStats ? '...' : '${coachStats['doorsLockingYes'] ?? 0}',
                          color: Colors.green,
                        ),
                        _tableCell(
                          isLoadingStats ? '...' : '${coachStats['doorsLockingNo'] ?? 0}',
                          color: Colors.red,
                        ),
                        _tableCell('0', color: Colors.grey),
                      ],
                    ),
                    // Watering Row
                    TableRow(
                      children: [
                        _tableCell('Watering Completed', isLabel: true),
                        _tableCell(
                          isLoadingStats ? '...' : '${coachStats['wateringYes'] ?? 0}',
                          color: Colors.green,
                        ),
                        _tableCell(
                          isLoadingStats ? '...' : '${coachStats['wateringNo'] ?? 0}',
                          color: Colors.red,
                        ),
                        _tableCell('0', color: Colors.grey),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              const Text(
                "RESOURCE SHORTAGES",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _shortageBox(
                    "Manpower\nShortage",
                    "NA",
                    "Personnel",
                    Colors.red.shade400,
                  ),
                  _shortageBox(
                    "Machine\nShortage",
                    "NA",
                    "Equipment",
                    Colors.red.shade400,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _tableCell(String text, {bool isLabel = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(
        text,
        textAlign: isLabel ? TextAlign.left : TextAlign.center,
        style: TextStyle(
          fontSize: isLabel ? 13 : 15,
          fontWeight: isLabel ? FontWeight.w500 : FontWeight.bold,
          color: color ?? Colors.black87,
        ),
      ),
    );
  }

  Widget _expandableFilterContainer({
    required String title,
    required bool isExpanded,
    required VoidCallback onTap,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(14),
              bottom: isExpanded ? Radius.zero : Radius.circular(14),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(14),
                  bottom: isExpanded ? Radius.zero : Radius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: kRailwayBlue,
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: Container(),
            secondChild: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 300),
          ),
        ],
      ),
    );
  }

  Widget _buildCTSTab() {
    final user = Provider.of<AuthProvider>(context).currentUser;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _expandableFilterContainer(
            title: "Filter Reports",
            isExpanded: _isCTSFilterExpanded,
            onTap: () {
              setState(() {
                _isCTSFilterExpanded = !_isCTSFilterExpanded;
              });
            },
            children: [
                  if (user != null)
                    ZoneDivisionDepotDropdowns(
                      user: user,
                      onChangedWithZone: (zone, division, depot) {
                        setState(() {
                          _selectedFilterZone = zone;
                          _selectedFilterDivision = division;
                          _selectedFilterDepot = depot;
                        });
                      },
                    ),

              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _textField("Train No", (v) => trainNo = v)),
                  const SizedBox(width: 10),
                  Expanded(child: _textField("Coach No", (v) => coachNo = v)),
                ],
              ),
              const SizedBox(height: 12),
              _dateRangePicker(),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.assessment, color: Colors.white),
                label: const Text(
                  "Generate Report",
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                onPressed: isLoading ? null : _generateCTSReport,
              ),
            ],
          ),

          const SizedBox(height: 25),

          _summaryContainer(
            title: "CTS Form Statistics",
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: [
                  _summaryCard(
                    title: "Total Trains / Coaches Cleaned",
                    value: isLoadingStats
                        ? "..."
                        : "${(ctsStats['statistics']?['totalTrains']?.toString() ?? "0")} / ${ctsStats['statistics']?['totalCoachesCleaned'] ?? "0%"}",
                    color: Colors.blue,
                  ),
                  _summaryCard(
                    title: "Total unattended coaches",
                    value: isLoadingStats
                        ? "..."
                        : (ctsStats['statistics']?['totalUnattendedCoaches']?.toString() ?? "0"),
                    color: Colors.orange,
                  ),
                  _summaryCard(
                    title: "Sampled Coaches / Percentage",
                    value: isLoadingStats
                        ? "..."
                        : "${ctsStats['statistics']?['sampledCoaches']?.toString() ?? "0"} / ${ctsStats['statistics']?['samplingPercentage'] ?? "0%"}",
                    color: Colors.teal,
                  ),
                  _summaryCard(
                    title: "Average Window Time",
                    value: isLoadingStats
                        ? "..."
                        : ctsStats['statistics']?['averageWindowTime']?.toString() ?? "0 Min",
                    color: Colors.red,
                  ),
                ],
              ),
              const Text(
                "Overall Grade Distribution",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),

              _buildCTSGradeRow(
                  isLoadingStats, ctsStats
              ),

              const SizedBox(height: 24),

              const Text(
                "CLEANING OPERATIONS SUMMARY",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),

              Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _performanceSummary(
                    title: "Toilet\nOccupied",
                    done: isLoadingStats
                        ? "..."
                        : (ctsStats['cleaningOperations']?['toiletOccupied']?.toString() ?? "0"),
                  ),
                  _performanceSummary(
                    title: "Average\nScore",
                    done: isLoadingStats
                        ? "..."
                        : (ctsStats['cleaningOperations']?['averageScore']?.toString() ?? "0"),
                  ),
                  _performanceSummary(
                    title: "Toilet\nUnattended",
                    done: isLoadingStats
                        ? "..."
                        : (ctsStats['cleaningOperations']?['toiletUnattended']?.toString() ?? "0"),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              const Text(
                "RESOURCE USED",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                alignment: WrapAlignment.spaceEvenly,
                spacing: 12,
                runSpacing: 12,
                children: [
                  _shortageBox(
                    "Manpower\nUses",
                    isLoadingStats
                        ? "..."
                        : (ctsStats['resourcesUsed']?['manpowerTotal']?.toString() ?? "0"),
                    "Total",
                    Colors.red.shade400,
                  ),
                  _shortageBox(
                    "Chemical\nUses",
                    isLoadingStats
                        ? "..."
                        : (ctsStats['resourcesUsed']?['chemicalQuantity']?.toString() ?? "0"),
                    "Liter",
                    Colors.red.shade400,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCTSGradeRow(bool isLoadingStats, Map<String, dynamic> ctsStats) {
    final gradeDistribution = ctsStats['gradeDistribution'] ?? {};
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kRailwayBlue),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _gradeItem(
            grade: 'A',
            count: isLoadingStats ? '...' : '${gradeDistribution['A']?['count'] ?? 0}',
            percent: isLoadingStats
                ? '...'
                : '${gradeDistribution['A']?['pct'] ?? '0.0'}%',
            color: Colors.green,
          ),
          _verticalDivider(),
          _gradeItem(
            grade: 'B',
            count: isLoadingStats ? '...' : '${gradeDistribution['B']?['count'] ?? 0}',
            percent: isLoadingStats
                ? '...'
                : '${gradeDistribution['B']?['pct'] ?? '0.0'}%',
            color: Colors.blue,
          ),
          _verticalDivider(),
          _gradeItem(
            grade: 'C',
            count: isLoadingStats ? '...' : '${gradeDistribution['C']?['count'] ?? 0}',
            percent: isLoadingStats
                ? '...'
                : '${gradeDistribution['C']?['pct'] ?? '0.0'}%',
            color: Colors.orange,
          ),
          _verticalDivider(),
          _gradeItem(
            grade: 'D',
            count: isLoadingStats ? '...' : '${gradeDistribution['D']?['count'] ?? 0}',
            percent: isLoadingStats
                ? '...'
                : '${gradeDistribution['D']?['pct'] ?? '0.0'}%',
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _filterContainer({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _summaryContainer({
    required String title,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.green,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }


  Widget _performanceSummary({
    required String title,
    required String done,
  }) {
    return Container(
      width: 105,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kRailwayBlue.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            done,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: kRailwayBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shortageBox(
    String title,
    String value,
    String subtitle,
    Color color,
  ) {
    return Container(
      width: 140,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _dateRangePicker() {
    return GestureDetector(
      onTap: _selectDateRange,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              startDate == null
                  ? "Date Range"
                  : "${DateFormat('dd MMM yyyy').format(startDate!)} - ${DateFormat('dd MMM yyyy').format(endDate!)}",
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const Icon(Icons.calendar_today, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _multiSelectTile({
    required String label,
    required List<String> items,
    required List<String> selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                selected.isEmpty ? "Select $label" : selected.join(", "),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Future<List<String>?> _showMultiSelectDialog(
    List<String> items,
    List<String> selected,
  ) async {
    final temp = List<String>.from(selected);
    return showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Select Items"),
        content: SingleChildScrollView(
          child: Column(
            children: items
                .map(
                  (item) => StatefulBuilder(
                    builder: (context, setStateDialog) => CheckboxListTile(
                      title: Text(item),
                      value: temp.contains(item),
                      onChanged: (v) {
                        if (v == true) {
                          temp.add(item);
                        } else {
                          temp.remove(item);
                        }
                        setStateDialog(() {});
                      },
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, temp),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Widget _textField(String hint, Function(String) onChanged) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      height: 45,
      child: TextFormField(
        decoration: InputDecoration(
          contentPadding: EdgeInsets.only(left: 10, bottom: 5),
          hintStyle: TextStyle(fontSize: 13),
          hintText: hint,
          border: InputBorder.none,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _summaryCard({
    required String title,
    required String value,
    required Color color,
    bool isMoney = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: isMoney ? 18 : 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradeItem({
    required String grade,
    required String count,
    required String percent,
    required Color color,
  }) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            grade,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            percent,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(height: 40, width: 1, color: Colors.grey.shade300);
  }

  Widget _buildOBHSTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _expandableFilterContainer(
            title: "Filter Reports",
            isExpanded: _isOBHSFilterExpanded,
            onTap: () {
              setState(() {
                _isOBHSFilterExpanded = !_isOBHSFilterExpanded;
              });
            },
            children: [
              Row(
                children: [
                  Expanded(child: _textField("Train Name/No", (v) => selectedOBHSTrain = v)),
                  const SizedBox(width: 10),
                  Expanded(child: _textField("Instance No", (v) => selectedOBHSInstance = int.tryParse(v))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _textField("Coach No", (v) => selectedOBHSCoach = v)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      height: 45,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Checkbox(
                            value: includeCompleteTrainData,
                            onChanged: (v) {
                              setState(() {
                                includeCompleteTrainData = v ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Text(
                              'Complete Train',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _dateRangePicker(),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                value: selectedReportType,
                decoration: InputDecoration(
                  hint: Text('Select Report'),
                  contentPadding: EdgeInsets.all(8),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(
                      color: Colors.grey
                    )
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.grey.shade300
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: [
                  "Train Report",
                  "Attendance Report",
                  "Worker Activity Report",
                  "Complaint Report"
                ].map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Text(type,style: TextStyle(fontWeight: FontWeight.normal,fontSize: 13),),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    selectedReportType = value;
                  });
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.assessment, color: Colors.white),
                label: const Text(
                  "Generate Report",
                  style: TextStyle(color: Colors.white, fontSize: 15),
                ),
                onPressed: isLoading ? null : _generateOBHSReport,
              ),
            ],
          ),

          const SizedBox(height: 25),

          _summaryContainer(
            title: "Comprehensive Performance Summary",
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.5,
                children: [
                  _summaryCard(
                    title: "Total OBHS Trains",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['totalTrains']?.toString() ?? "0"),
                    color: Colors.blue,
                  ),
                  _summaryCard(
                    title: "Total Instances",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['totalInstances']?.toString() ?? "0"),
                    color: Colors.purple,
                  ),
                  _summaryCard(
                    title: "Active Instances",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['activeInstances']?.toString() ?? "0"),
                    color: Colors.green,
                  ),
                  _summaryCard(
                    title: "Completed Instances",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['completedInstances']?.toString() ?? "0"),
                    color: Colors.teal,
                  ),
                  _summaryCard(
                    title: "Total Workers Assigned",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['totalWorkersAssigned']?.toString() ?? "0"),
                    color: Colors.orange,
                  ),
                  _summaryCard(
                    title: "Active Coaches",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['totalCoaches']?.toString() ?? "0"),
                    color: Colors.indigo,
                  ),
                  _summaryCard(
                    title: "Coaches with Workers",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['coachesWithWorkers']?.toString() ?? "0"),
                    color: kSuccessGreen,
                  ),
                  _summaryCard(
                    title: "Jobs Completed",
                    value: isLoadingStats
                        ? "..."
                        : (obhsStats['jobsCompleted']?.toString() ?? "0"),
                    color: Colors.cyan,
                  ),
                ],
              ),

              const SizedBox(height: 24),

              const Text(
                "Instance Status Distribution",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kRailwayBlue),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _gradeItem(
                      grade: 'Active',
                      count: isLoadingStats ? '...' : (obhsStats['activeInstances']?.toString() ?? '0'),
                      percent: isLoadingStats
                          ? '...'
                          : obhsStats['totalInstances'] != null && obhsStats['totalInstances'] != 0
                              ? '${((obhsStats['activeInstances'] ?? 0) / obhsStats['totalInstances'] * 100).toStringAsFixed(1)}%'
                              : '0%',
                      color: Colors.green,
                    ),
                    _verticalDivider(),
                    _gradeItem(
                      grade: 'Pending',
                      count: isLoadingStats ? '...' : (obhsStats['pendingInstances']?.toString() ?? '0'),
                      percent: isLoadingStats
                          ? '...'
                          : obhsStats['totalInstances'] != null && obhsStats['totalInstances'] != 0
                              ? '${((obhsStats['pendingInstances'] ?? 0) / obhsStats['totalInstances'] * 100).toStringAsFixed(1)}%'
                              : '0%',
                      color: Colors.orange,
                    ),
                    _verticalDivider(),
                    _gradeItem(
                      grade: 'Completed',
                      count: isLoadingStats ? '...' : (obhsStats['completedInstances']?.toString() ?? '0'),
                      percent: isLoadingStats
                          ? '...'
                          : obhsStats['totalInstances'] != null && obhsStats['totalInstances'] != 0
                              ? '${((obhsStats['completedInstances'] ?? 0) / obhsStats['totalInstances'] * 100).toStringAsFixed(1)}%'
                              : '0%',
                      color: Colors.blue,
                    ),
                    _verticalDivider(),
                    _gradeItem(
                      grade: 'Closed',
                      count: isLoadingStats ? '...' : (obhsStats['closedInstances']?.toString() ?? '0'),
                      percent: isLoadingStats
                          ? '...'
                          : obhsStats['totalInstances'] != null && obhsStats['totalInstances'] != 0
                              ? '${((obhsStats['closedInstances'] ?? 0) / obhsStats['totalInstances'] * 100).toStringAsFixed(1)}%'
                              : '0%',
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              const Text(
                "WORKER ASSIGNMENT SUMMARY",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kRailwayBlue),
                  color: Colors.white,
                ),
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(2.5),
                    1: FlexColumnWidth(1),
                    2: FlexColumnWidth(1),
                  },
                  border: TableBorder.symmetric(
                    inside: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                  children: [

                    TableRow(
                      decoration: BoxDecoration(
                        color: kRailwayBlue.withOpacity(0.1),
                      ),
                      children: [
                        _tableHeaderCell('Category'),
                        _tableHeaderCell('Count'),
                        _tableHeaderCell('Percentage'),
                      ],
                    ),

                    TableRow(
                      children: [
                        _tableCell('Coaches with Workers', isLabel: true),
                        _tableCell(
                            isLoadingStats ? '...' : (obhsStats['coachesWithWorkers']?.toString() ?? '0'),
                            color: Colors.green),
                        _tableCell(
                            isLoadingStats
                                ? '...'
                                : obhsStats['totalCoaches'] != null && obhsStats['totalCoaches'] != 0
                                    ? '${((obhsStats['coachesWithWorkers'] ?? 0) / obhsStats['totalCoaches'] * 100).toStringAsFixed(0)}%'
                                    : '0%',
                            color: Colors.green),
                      ],
                    ),

                    TableRow(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                      ),
                      children: [
                        _tableCell('Coaches without Workers', isLabel: true),
                        _tableCell(
                            isLoadingStats ? '...' : (obhsStats['coachesWithoutWorkers']?.toString() ?? '0'),
                            color: Colors.red),
                        _tableCell(
                            isLoadingStats
                                ? '...'
                                : obhsStats['totalCoaches'] != null && obhsStats['totalCoaches'] != 0
                                    ? '${((obhsStats['coachesWithoutWorkers'] ?? 0) / obhsStats['totalCoaches'] * 100).toStringAsFixed(0)}%'
                                    : '0%',
                            color: Colors.red),
                      ],
                    ),
                    TableRow(
                      children: [
                        _tableCell('Total Active Workers', isLabel: true),
                        _tableCell(
                            isLoadingStats ? '...' : (obhsStats['totalWorkersAssigned']?.toString() ?? '0'),
                            color: kRailwayBlue),
                        _tableCell('100%', color: kRailwayBlue),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

            ],
          ),
        ],
      ),
    );
  }

  Widget _compactMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<void> _generateOBHSReport() async {
    if (selectedReportType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a report type.')),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      // ── Fetch run instances from the OBHS API (authoritative) ────────────
      final allRuns = await OBHSRepository.getAllRunInstances();
      final runInstances = allRuns
          .where((r) =>
              (selectedOBHSTrain == null || selectedOBHSTrain!.isEmpty || r.trainNo == selectedOBHSTrain))
          .map((r) => <String, dynamic>{
                'id': r.runInstanceId ?? r.id ?? '',
                'runInstanceId': r.runInstanceId ?? r.id ?? '',
                'instanceId': r.instanceId,
                'trainNo': r.trainNo,
                'trainName': r.trainName,
                'status': r.status,
                'departureDate': r.departureDate?.toIso8601String(),
                'coaches': r.coaches.map((c) => c.toJson()).toList(),
                'createdBy': r.createdBy,
              })
          .toList();

      if (runInstances.isEmpty) {
        setState(() {
          obhsReportGenerated = false;
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'No OBHS run data found for the selected filters. Create a run instance first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      setState(() {
        obhsReportData = runInstances;
        obhsReportGenerated = true;
        isLoading = false;
      });

      // Prompt download
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Report Ready'),
            content: Text(
                '${runInstances.length} run instance(s) found.\nDownload the ${selectedReportType!} Excel report?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                icon: const Icon(Icons.table_chart, color: Colors.white),
                label: const Text('Excel', style: TextStyle(color: Colors.white)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _injectRatings(runInstances.cast<Map<String, dynamic>>());
                  _downloadOBHSExcel(runInstances);
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                label: const Text('PDF', style: TextStyle(color: Colors.white)),
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _injectRatings(runInstances.cast<Map<String, dynamic>>());
                  _downloadOBHSPdf(runInstances);
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: kRailwayBlue),
                icon: const Icon(Icons.send, color: Colors.white),
                label: const Text('Email', style: TextStyle(color: Colors.white)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _sendOBHSEmailToHigherAuthority(runInstances);
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _sendOBHSEmailToHigherAuthority(List<dynamic> runInstances) async {
    setState(() => isDownloading = true);
    int successCount = 0;
    try {
      for (final run in runInstances) {
        final runId = run['runInstanceId']?.toString() ?? run['instanceId']?.toString() ?? run['id']?.toString() ?? '';
        if (runId.isNotEmpty) {
          String backendReportType = 'OPERATIONAL_AUDIT';
          if (selectedReportType == 'Attendance Report') backendReportType = 'ATTENDANCE_AUDIT';
          else if (selectedReportType == 'Worker Activity Report') backendReportType = 'WORKER_ACTIVITY_AUDIT';
          else if (selectedReportType == 'Complaint Report') backendReportType = 'COMPLAINT_AUDIT';
          
          await ApiService.sendAuditReportEmail(backendReportType, runId, 'hirenkodwani@gmail.com');
          successCount++;
        }
      }
      setState(() => isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Email successfully sent to Higher Authority for $successCount run(s).'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() => isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send email: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _injectRatings(List<Map<String, dynamic>> runs) async {
    setState(() => isDownloading = true);
    for (final run in runs) {
      final runId = run['runInstanceId']?.toString() ?? run['instanceId']?.toString() ?? '';
      if (runId.isNotEmpty) {
        try {
          final res = await WorkerRepository.getFeedbackSummary(runInstanceId: runId);
          final feedbacks = res['recentFeedbacks'] ?? res['data'] ?? [];
          
          double avgForType(String type) {
            final list = feedbacks.where((f) => f['raterType'] == type).toList();
            if (list.isEmpty) return 0;
            final sum = list.fold<double>(0, (s, f) => s + ((f['overallRating'] as num?)?.toDouble() ?? 0));
            return sum / list.length;
          }
          int countForType(String type) => feedbacks.where((f) => f['raterType'] == type).length;
          
          final passengerAvg = avgForType('Passenger');
          final officialAvg = avgForType('Official');
          final supervisorAvg = avgForType('Supervisor/Admin');
          final tteAvg = avgForType('TTE');
          final psmeAvg = avgForType('PSME');

          double totalWeight = 0, totalScore = 0;
          if (countForType('Passenger') > 0) { totalScore += passengerAvg * 0.40; totalWeight += 0.40; }
          if (countForType('Official') > 0) { totalScore += officialAvg * 0.25; totalWeight += 0.25; }
          if (countForType('Supervisor/Admin') > 0) { totalScore += supervisorAvg * 0.20; totalWeight += 0.20; }
          if (countForType('TTE') > 0) { totalScore += tteAvg * 0.10; totalWeight += 0.10; }
          if (countForType('PSME') > 0) { totalScore += psmeAvg * 0.05; totalWeight += 0.05; }
          
          run['weightedScore'] = totalWeight > 0 ? (totalScore / totalWeight).toStringAsFixed(2) : '-';

          for (var c in (run['coaches'] as List<dynamic>? ?? [])) {
            final cm = c as Map<String, dynamic>;
            final coachNo = cm['coachNo'] ?? cm['coachPosition']?.toString();
            final cFeedbacks = feedbacks.where((f) => f['coachNo'] == coachNo && f['raterType'] == 'Passenger').toList();
            if (cFeedbacks.isNotEmpty) {
              final sum = cFeedbacks.fold<double>(0, (s, f) => s + ((f['overallRating'] as num?)?.toDouble() ?? 0));
              cm['passengerRating'] = (sum / cFeedbacks.length).toStringAsFixed(1);
            } else {
              cm['passengerRating'] = '-';
            }
          }
        } catch (e) {
          run['weightedScore'] = '-';
        }
      }
    }
  }

  Future<void> _downloadOBHSPdf(List<dynamic> runInstances) async {
    setState(() => isDownloading = true);
    try {
      final runs = runInstances.cast<Map<String, dynamic>>();
      Uint8List? pdfBytes;

      switch (selectedReportType) {
        case 'Train Report':
          pdfBytes = await PDFReportService.generateTrainReportPdf(runs);
          break;
        case 'Attendance Report':
          final allAttendance = <Map<String, dynamic>>[];
          for (final run in runs) {
            final runId = run['runInstanceId']?.toString() ?? run['instanceId']?.toString() ?? '';
            if (runId.isNotEmpty) {
              allAttendance.addAll(await OBHSRepository.getAttendanceList(runInstanceId: runId));
            }
          }
          pdfBytes = await PDFReportService.generateAttendanceReportPdf(runs, allAttendance);
          break;
        case 'Worker Activity Report':
          final allTasks = <Map<String, dynamic>>[];
          for (final run in runs) {
            final runId = run['runInstanceId']?.toString() ?? run['instanceId']?.toString() ?? '';
            if (runId.isNotEmpty) {
              allTasks.addAll(await OBHSRepository.getRunTasks(runId));
            }
          }
          pdfBytes = await PDFReportService.generateWorkerActivityReportPdf(runs, allTasks);
          break;
        case 'Complaint Report':
          final allComplaints = <Map<String, dynamic>>[];
          for (final run in runs) {
            final runId = run['runInstanceId']?.toString() ?? run['instanceId']?.toString() ?? '';
            if (runId.isNotEmpty) {
              allComplaints.addAll(await OBHSRepository.getRunComplaints(runId));
            }
          }
          pdfBytes = await PDFReportService.generateComplaintReportPdf(runs, allComplaints);
          break;
        default:
          pdfBytes = await PDFReportService.generateTrainReportPdf(runs);
      }

      setState(() => isDownloading = false);
      
      if (pdfBytes != null) {
        final typeSlug = (selectedReportType ?? 'report').toLowerCase().replaceAll(' ', '_');
        final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        await Printing.sharePdf(bytes: pdfBytes, filename: 'OBHS_${typeSlug}_$timestamp.pdf');
      }
    } catch (e) {
      setState(() => isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _downloadOBHSExcel(List<dynamic> runInstances) async {
    setState(() => isDownloading = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final typeSlug = (selectedReportType ?? 'report')
          .toLowerCase()
          .replaceAll(' ', '_');
      final path = '${dir.path}/OBHS_${typeSlug}_$timestamp.xlsx';

      File file;
      final runs = runInstances.cast<Map<String, dynamic>>();

      switch (selectedReportType) {
        case 'Train Report':
          file = await OBHSReportExcelGenerator.generateTrainRunReport(
              runs, path);
          break;

        case 'Attendance Report':
          // Fetch attendance for all runs
          final allAttendance = <Map<String, dynamic>>[];
          for (final run in runs) {
            final runId = run['runInstanceId']?.toString() ??
                run['instanceId']?.toString() ?? '';
            if (runId.isNotEmpty) {
              final att = await OBHSRepository.getAttendanceList(runInstanceId: runId);
              allAttendance.addAll(att);
            }
          }
          file = await OBHSReportExcelGenerator.generateAttendanceReport(
              runs, allAttendance, path);
          break;

        case 'Worker Activity Report':
          final allTasks = <Map<String, dynamic>>[];
          for (final run in runs) {
            final runId = run['runInstanceId']?.toString() ??
                run['instanceId']?.toString() ?? '';
            if (runId.isNotEmpty) {
              final tasks = await OBHSRepository.getRunTasks(runId);
              allTasks.addAll(tasks);
            }
          }
          file = await OBHSReportExcelGenerator.generateWorkerActivityReport(
              runs, allTasks, path);
          break;

        case 'Complaint Report':
          final allComplaints = <Map<String, dynamic>>[];
          for (final run in runs) {
            final runId = run['runInstanceId']?.toString() ??
                run['instanceId']?.toString() ?? '';
            if (runId.isNotEmpty) {
              final cmps = await OBHSRepository.getRunComplaints(runId);
              allComplaints.addAll(cmps);
            }
          }
          file = await OBHSReportExcelGenerator.generateComplaintReport(
              runs, allComplaints, path);
          break;

        default:
          file = await OBHSReportExcelGenerator.generateTrainRunReport(
              runs, path);
      }

      setState(() => isDownloading = false);
      await OpenFilex.open(file.path);
    } catch (e) {
      setState(() => isDownloading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }
}
