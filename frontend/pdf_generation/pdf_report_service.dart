// pdf_report_service.dart - COMPLETE FIXED VERSION WITH PROPER LAYOUT
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';

// Configuration class
class PDFReportConfig {
  final int recordsPerPage;
  final bool includeCharts;
  final bool includeSummary;
  
  const PDFReportConfig({
    this.recordsPerPage = 20,
    this.includeCharts = true,
    this.includeSummary = true,
  });
}

// MonthlyStats class
class MonthlyStats {
  final int totalMovements;
  final int checkIns;
  final int checkOuts;
  final String avgTimeOutside;
  final String longestDuration;
  final String mostActiveDay;
  final String peakHour;
  final String monthDuration;

  MonthlyStats({
    required this.totalMovements,
    required this.checkIns,
    required this.checkOuts,
    required this.avgTimeOutside,
    required this.longestDuration,
    required this.mostActiveDay,
    required this.peakHour,
    required this.monthDuration,
  });
}

class PDFReportService {
  static final PDFReportService _instance = PDFReportService._internal();
  factory PDFReportService() => _instance;
  PDFReportService._internal();

  // Constants for consistent styling
  static const PdfColor primaryColor = PdfColors.blue800;
  static const PdfColor secondaryColor = PdfColors.blue600;
  static const PdfColor accentColor = PdfColors.orange;
  static const PdfColor successColor = PdfColors.green;
  static const double fontSizeTitle = 22.0;
  static const double fontSizeSubtitle = 16.0;
  static const double fontSizeBody = 12.0;
  static const int recordsPerPage = 4;
  static const int tableRowsPerPage = 25;

  // Generate movement logs PDF with 2-month summary
  Future<String> generateMovementLogsPDF({
    required List<dynamic> movementRecords,
    required String studentName,
    required String rollNo,
    required String hostel,
    PDFReportConfig config = const PDFReportConfig(),
  }) async {
    try {
      // Input validation
      if (movementRecords.isEmpty) {
        throw Exception('No movement records provided');
      }
      if (studentName.isEmpty || rollNo.isEmpty || hostel.isEmpty) {
        throw Exception('Student information is incomplete');
      }

      final pdf = pw.Document();
      
      print('📊 Starting PDF generation for $studentName');
      print('📋 Total records to process: ${movementRecords.length}');
      
      // Calculate date ranges for current and previous month
      final now = DateTime.now();
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final currentMonthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);
      
      // Handle year rollover for previous month
      final prevMonth = now.month == 1 ? 12 : now.month - 1;
      final prevYear = now.month == 1 ? now.year - 1 : now.year;
      final previousMonthStart = DateTime(prevYear, prevMonth, 1);
      final previousMonthEnd = DateTime(prevYear, prevMonth + 1, 0, 23, 59, 59, 999);

      // Filter records for both months
      final currentMonthRecords = _filterRecordsByDateRange(
        movementRecords, 
        currentMonthStart, 
        currentMonthEnd
      );
      
      final previousMonthRecords = _filterRecordsByDateRange(
        movementRecords, 
        previousMonthStart, 
        previousMonthEnd
      );

      print('📊 Filtered records - Current month: ${currentMonthRecords.length}');
      print('📊 Filtered records - Previous month: ${previousMonthRecords.length}');

      // Calculate page counts for structure overview
      final currentDailyBreakdown = _calculateCompleteDailyBreakdown(currentMonthStart, currentMonthEnd, currentMonthRecords);
      final currentDailyDurations = _calculateDailyTotalMinutes(currentMonthStart, currentMonthEnd, currentMonthRecords);

      final previousDailyBreakdown = _calculateCompleteDailyBreakdown(previousMonthStart, previousMonthEnd, previousMonthRecords);
      final previousDailyDurations = _calculateDailyTotalMinutes(previousMonthStart, previousMonthEnd, previousMonthRecords);

      
      final currentMonthTablePages = (currentDailyBreakdown.length / tableRowsPerPage).ceil();
      final previousMonthTablePages = (previousDailyBreakdown.length / tableRowsPerPage).ceil();
      final currentDetailPages = (currentMonthRecords.length / recordsPerPage).ceil();
      final previousDetailPages = (previousMonthRecords.length / recordsPerPage).ceil();

      // Calculate total pages for footer numbering
      final totalPages = 1 + // Header page
                        1 + // Monthly comparison page
                        currentMonthTablePages + 
                        previousMonthTablePages + 
                        currentDetailPages + 
                        previousDetailPages;

      // Page number tracking
      int currentPageNumber = 1;

      // Add header page (Page 1 - no number displayed)
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return _buildHeaderPage(
              studentName: studentName,
              rollNo: rollNo,
              hostel: hostel,
              currentMonth: _getMonthName(now.month),
              previousMonth: _getMonthName(prevMonth),
              currentYear: now.year,
              previousYear: prevYear,
              currentMonthRecords: currentMonthRecords.length,
              previousMonthRecords: previousMonthRecords.length,
              currentMonthTablePages: currentMonthTablePages,
              previousMonthTablePages: previousMonthTablePages,
              currentDetailPages: currentDetailPages,
              previousDetailPages: previousDetailPages,
              currentPageNumber: 2,
            );
          },
        ),
      );
      currentPageNumber++;

      // Add monthly comparison analysis page (Page 2)
      final monthlyComparisonPageNumber = currentPageNumber;
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return _buildPageWithNumber(
              content: _buildMonthlyComparisonPage(
                currentMonthRecords: currentMonthRecords,
                previousMonthRecords: previousMonthRecords,
                currentMonth: _getMonthName(now.month),
                previousMonth: _getMonthName(prevMonth),
                currentMonthStart: currentMonthStart,
                currentMonthEnd: currentMonthEnd,
                previousMonthStart: previousMonthStart,
                previousMonthEnd: previousMonthEnd,
              ),
              pageNumber: monthlyComparisonPageNumber,
              totalPages: totalPages,
            );
          },
        ),
      );
      currentPageNumber++;

      // Add paginated current month tables
      final currentMonthTablePageList = _buildPaginatedDailyActivityTables(
        dailyBreakdown: currentDailyBreakdown,
        dailyDurations: currentDailyDurations,
        monthName: _getMonthName(now.month),
        monthYear: now.year,
        startPageNumber: currentPageNumber,
        totalPages: totalPages,
      );

      for (final page in currentMonthTablePageList) {
        pdf.addPage(page);
        currentPageNumber++;
      }

      // Add paginated previous month tables
      final previousMonthTablePageList = _buildPaginatedDailyActivityTables(
        dailyBreakdown: previousDailyBreakdown,
        dailyDurations: previousDailyDurations,
        monthName: _getMonthName(prevMonth),
        monthYear: prevYear,
        startPageNumber: currentPageNumber,
        totalPages: totalPages,
      );

      for (final page in previousMonthTablePageList) {
        pdf.addPage(page);
        currentPageNumber++;
      }

      // Add detailed records pages for current month
      print('🔍 DEBUG: Generating current month detail pages...');
      final currentMonthPages = _buildMonthlyDetailPages(
        records: currentMonthRecords,
        monthName: _getMonthName(now.month),
        year: now.year,
        monthStart: currentMonthStart,
        monthEnd: currentMonthEnd,
        startPageNumber: currentPageNumber,
        totalPages: totalPages,
      );
      
      if (currentMonthPages.isNotEmpty) {
        for (var page in currentMonthPages) {
          pdf.addPage(page);
          currentPageNumber++;
        }
        print('✅ Added ${currentMonthPages.length} detail pages for current month');
      } else {
        print('❌ No detail pages generated for current month');
      }

      // Add detailed records pages for previous month
      print('🔍 DEBUG: Generating previous month detail pages...');
      final previousMonthPages = _buildMonthlyDetailPages(
        records: previousMonthRecords,
        monthName: _getMonthName(prevMonth),
        year: prevYear,
        monthStart: previousMonthStart,
        monthEnd: previousMonthEnd,
        startPageNumber: currentPageNumber,
        totalPages: totalPages,
      );

      if (previousMonthPages.isNotEmpty) {
        for (var page in previousMonthPages) {
          pdf.addPage(page);
          currentPageNumber++;
        }
        print('✅ Added ${previousMonthPages.length} detail pages for previous month');
      } else {
        print('❌ No detail pages generated for previous month');
      }

      // Save PDF to file
      return await _savePDF(pdf, '$rollNo-movement-logs-${now.month}-${now.year}');
    } catch (e, stackTrace) {
      print('❌ PDF Generation Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  // FIXED: Build monthly detail pages - PROPER PAGINATION
  List<pw.Page> _buildMonthlyDetailPages({
    required List<dynamic> records,
    required String monthName,
    required int year,
    required DateTime monthStart,
    required DateTime monthEnd,
    required int startPageNumber,
    required int totalPages,
  }) {
    final pages = <pw.Page>[];
    
    print('🚀 BUILDING DETAILED MOVEMENT RECORDS for $monthName $year');
    print('📊 Total records: ${records.length}');
    print('📄 Start page number: $startPageNumber');
    print('📑 Total pages in document: $totalPages');
    print('🔢 Records per page: $recordsPerPage');
    
    // Safety check - return empty if no records
    if (records.isEmpty) {
      print('❌ No records found for $monthName - skipping detail pages');
      return pages;
    }

    // Calculate pagination
    final totalDetailPages = (records.length / recordsPerPage).ceil();
    print('🔢 Will create $totalDetailPages detail pages');
    print('🔢 Math: ${records.length} / $recordsPerPage = ${records.length / recordsPerPage} -> ceil = $totalDetailPages');
    
    // Sort records by date (oldest first)
    final sortedRecords = List.from(records);
    sortedRecords.sort((a, b) {
      final aOut = _parseDateTime(a['out_time']);
      final aIn  = _parseDateTime(a['in_time']);
      final bOut = _parseDateTime(b['out_time']);
      final bIn  = _parseDateTime(b['in_time']);

      final dateA = aOut ?? aIn ?? DateTime(0);
      final dateB = bOut ?? bIn ?? DateTime(0);

      return dateA.compareTo(dateB); // oldest first
    });

    // FIXED: Create pages - ensure we process ALL records
    for (var pageIndex = 0; pageIndex < totalDetailPages; pageIndex++) {
      final startIndex = pageIndex * recordsPerPage;
      final endIndex = (startIndex + recordsPerPage) <= sortedRecords.length 
          ? startIndex + recordsPerPage 
          : sortedRecords.length;
      
      // DOUBLE CHECK: Make sure we don't go out of bounds
      if (startIndex >= sortedRecords.length) {
        print('⚠️ Start index $startIndex exceeds record count ${sortedRecords.length} - stopping');
        break;
      }
      
      final pageRecords = sortedRecords.sublist(startIndex, endIndex);
      final currentDetailPage = pageIndex + 1;
      final displayPageNumber = startPageNumber + pageIndex;
      
      print('📝 Creating page $currentDetailPage/$totalDetailPages with ${pageRecords.length} records');
      print('📊 Records range: $startIndex to ${endIndex-1} of ${sortedRecords.length} total');
      print('🔢 Display page number: $displayPageNumber');

      pages.add(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return _buildDetailPageContent(
              records: pageRecords,
              monthName: monthName,
              year: year,
              currentPage: currentDetailPage,
              totalPages: totalDetailPages,
              displayPageNumber: displayPageNumber,
              totalDocumentPages: totalPages,
            );
          },
        ),
      );
      
      // Debug: Print first and last record of this page
      if (pageRecords.isNotEmpty) {
        print('📄 Page $currentDetailPage first record: ${_formatDateTime(pageRecords.first['out_time'])}');
        print('📄 Page $currentDetailPage last record: ${_formatDateTime(pageRecords.last['out_time'])}');
      }
    }
    
    print('✅ SUCCESS: Built ${pages.length} detailed movement record pages for $monthName');
    print('📊 Expected pages: $totalDetailPages, Actual pages: ${pages.length}');
    return pages;
  }

  // FIXED: Detail page content with proper layout
  pw.Widget _buildDetailPageContent({
    required List<dynamic> records,
    required String monthName,
    required int year,
    required int currentPage,
    required int totalPages,
    required int displayPageNumber,
    required int totalDocumentPages,
  }) {
    // ADD DEBUG INFO
    print('🔍 DEBUG: Building detail page $currentPage/$totalPages with ${records.length} records');
    for (var i = 0; i < records.length; i++) {
      final record = records[i];
      print('  Record $i: ${_formatDateTime(record['out_time'])}');
    }

    return pw.Container(
      child: pw.Column(
        children: [
          // Header section
          _buildDetailPageHeader(monthName, year, currentPage, totalPages),
          
          pw.SizedBox(height: 10),
          
          // Records list - FIXED: Use Expanded to take available space
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (var record in records)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8), // REDUCED from 14
                    child: _buildDetailedRecordItem(record),
                  ),
              ],
            ),
          ),
          
          // Page number footer - FIXED: Use consistent styling
          pw.SizedBox(height: 10),
          _buildPageFooter(displayPageNumber, totalDocumentPages),
        ],
      ),
    );
  }

  // FIXED: Detail page header
  pw.Widget _buildDetailPageHeader(
    String monthName, 
    int year, 
    int currentPage, 
    int totalPages
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'DETAILED MOVEMENT RECORDS - PAGE $currentPage OF $totalPages', // MADE MORE PROMINENT
          style: pw.TextStyle(
            fontSize: 16, // REDUCED from 20
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),
        
        pw.SizedBox(height: 5),
        
        pw.Text(
          '$monthName $year',
          style: const pw.TextStyle(
            fontSize: 12,
            color: PdfColors.grey600,
          ),
        ),
        
        pw.SizedBox(height: 10),
        
        pw.Divider(
          color: PdfColors.grey400,
          thickness: 1,
        ),
      ],
    );
  }

  // FIXED: Improved detailed record item with reduced spacing
  pw.Widget _buildDetailedRecordItem(dynamic record) {
    final isCheckOut = record['action'] == 'out';
    final outTime = record['out_time'] ?? 'N/A';
    final inTime = record['in_time'];
    final duration = record['time_spent_minutes'];
    final recordedBy = record['recorded_by'] ?? 'Unknown';
    
    final dateTime = _parseDateTime(outTime);
    final formattedDate = dateTime != null 
        ? '${_formatDate(dateTime)} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}'
        : outTime.toString();

    return pw.Container(
      width: double.infinity,
      margin: const pw.EdgeInsets.only(bottom: 8), // REDUCED from 12
      padding: const pw.EdgeInsets.all(12), // REDUCED from 16
      decoration: pw.BoxDecoration(
        color: isCheckOut ? PdfColors.orange50 : PdfColors.green50,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(
          color: isCheckOut ? PdfColors.orange200 : PdfColors.green200,
          width: 1,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Header row with type and date
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              // Type badge
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4), // REDUCED
                decoration: pw.BoxDecoration(
                  color: isCheckOut ? PdfColors.orange : PdfColors.green,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(20)),
                ),
                child: pw.Text(
                  isCheckOut ? 'DEPARTURE' : 'ARRIVAL',
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 9, // REDUCED from 10
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              
              // Date and time
              pw.Text(
                formattedDate,
                style: const pw.TextStyle(
                  fontSize: 10, // REDUCED from 11
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ),
          
          pw.SizedBox(height: 8), // REDUCED from 12
          
          // Details in a clean layout
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Action Type:', isCheckOut ? 'Checked Out' : 'Checked In'),
              
              if (inTime != null) 
                _buildDetailRow('Return Time:', _formatDateTime(inTime)),
              
              if (duration != null) 
                _buildDetailRow('Time Spent:', _formatDuration(duration)),
              
              _buildDetailRow('Recorded By:', recordedBy),
            ],
          ),
        ],
      ),
    );
  }

  // FIXED: Helper for detail rows
  pw.Widget _buildDetailRow(String label, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 4), // REDUCED from 6
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 80, // REDUCED from 100
            child: pw.Text(
              label,
              style: const pw.TextStyle(
                fontSize: 9, // REDUCED from 10
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey600,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(
                fontSize: 9, // REDUCED from 10
                color: PdfColors.grey800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // FIXED: Page footer with consistent styling
  pw.Widget _buildPageFooter(int pageNumber, int totalPages) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 10),
      alignment: pw.Alignment.center,
      child: pw.Text(
        'Page $pageNumber of $totalPages',
        style: pw.TextStyle(
          fontSize: 10,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  // Build paginated daily activity tables with page numbers
  List<pw.Page> _buildPaginatedDailyActivityTables({
    required Map<String, int> dailyBreakdown,
    required Map<String, double> dailyDurations, 
    required String monthName,
    required int monthYear,
    required int startPageNumber,
    required int totalPages,
  }) {
    final pages = <pw.Page>[];
    
    // Convert to list and sort by date
    final entries = dailyBreakdown.entries.toList();
    entries.sort((a, b) {
      final dateA = _parseDateTime('${a.key} 00:00:00');
      final dateB = _parseDateTime('${b.key} 00:00:00');
      return dateA?.compareTo(dateB ?? DateTime.now()) ?? 0;
    });
   
    final grandTotalMovements = entries.fold<int>(0, (sum, e) => sum + e.value);
    final totalDays = entries.length;
    final activeDays = entries.where((entry) => entry.value > 0).length;
    final inactiveDays = totalDays - activeDays;

    // Split entries into chunks for pagination
    for (var i = 0; i < entries.length; i += tableRowsPerPage) {
      final endIndex = i + tableRowsPerPage > entries.length ? entries.length : i + tableRowsPerPage;
      final pageEntries = entries.sublist(i, endIndex);
      final currentPage = (i ~/ tableRowsPerPage) + 1;
      final totalTablePages = (entries.length / tableRowsPerPage).ceil();
      final displayPageNumber = startPageNumber + (i ~/ tableRowsPerPage);

      pages.add(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            return _buildPageWithNumber(
              content: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'DAILY ACTIVITY BREAKDOWN - $monthName $monthYear',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: primaryColor,
                    ),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Table $currentPage of $totalTablePages | Total: $totalDays days | Active: $activeDays | Inactive: $inactiveDays',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.SizedBox(height: 15),
                  _buildDailyActivityTable(pageEntries, currentPage, totalTablePages, grandTotalMovements, dailyDurations),
                ],
              ),
              pageNumber: displayPageNumber,
              totalPages: totalPages,
            );
          },
        ),
      );
    }

    print('📄 Generated ${pages.length} pages for $monthName with ${entries.length} days');
    return pages;
  }

  // Build page with footer page number
  pw.Widget _buildPageWithNumber({
    required pw.Widget content,
    required int pageNumber,
    required int totalPages,
  }) {
    return pw.Column(
      children: [
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 20),
            child: content,
          ),
        ),
        _buildPageFooter(pageNumber, totalPages),
      ],
    );
  }

  // Simple table builder without Expanded
  pw.Widget _buildDailyActivityTable(
    List<MapEntry<String, int>> entries,
    int currentPage,
    int totalPages,
    int grandTotalMovements,
    Map<String, double> dailyDurations, 
  ) {
    final tableRows = <pw.TableRow>[];
    
    // Header row
    tableRows.add(
      pw.TableRow(
        decoration: pw.BoxDecoration(color: PdfColors.blue100),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Day', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Movements', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(6),
            child: pw.Text('Total Time Outside', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
          ),
        ],
      ),
    );

    // Data rows
    for (final entry in entries) {
      final date = entry.key;
      final movements = entry.value;
      final dateTime = _parseDateTime('$date 00:00:00');
      final dayName = dateTime != null ? _getDayOfWeek(dateTime.weekday) : 'Unknown';

      // Get exact total minutes for this date (default 0.0)
      final totalMinutes = dailyDurations[date] ?? 0.0;
      final totalMinutesString = '${totalMinutes.toStringAsFixed(3)} min';

      tableRows.add(
        pw.TableRow(
          children: [
            // Date
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(date, style: const pw.TextStyle(fontSize: 9)),
            ),
            // Day
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(dayName, style: const pw.TextStyle(fontSize: 9)),
            ),
            // Movements
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                movements.toString(),
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: movements > 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: movements > 0 ? PdfColors.blue800 : PdfColors.grey600,
                ),
              ),
            ),
            // Total Time Outside (exact minutes)
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                totalMinutesString,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: totalMinutes > 0 ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: totalMinutes > 0 ? PdfColors.blue800 : PdfColors.grey600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Calculate total minutes for the entire month (exact)
    final grandTotalMinutes = entries.fold<double>(
      0.0,
      (sum, e) => sum + (dailyDurations[e.key] ?? 0.0),
    );

    if (currentPage == totalPages) {
      // FULL MONTH total time outside (all days)
      final grandTotalMinutes = dailyDurations.values.fold<double>(
        0.0,
        (sum, val) => sum + val,
      );

      tableRows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            // Summary label
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                'Summary',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              ),
            ),
            // Day empty
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(''),
            ),
            // Full month movement count
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                grandTotalMovements.toString(),
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: PdfColors.blue800,
                ),
              ),
            ),
            // FULL MONTH total time outside (3 decimal places)
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text(
                '${grandTotalMinutes.toStringAsFixed(3)} min',
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                  color: PdfColors.blue800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.3),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(0.8),
        3: const pw.FlexColumnWidth(0.9),
      },
      children: tableRows,
    );
  }

  // Improved date range filtering
  List<dynamic> _filterRecordsByDateRange(
    List<dynamic> records,
    DateTime startDate,
    DateTime endDate,
  ) {
    final filteredRecords = <dynamic>[];

    for (var record in records) {
      final outDate = _parseDateTime(record['out_time']);
      final inDate = _parseDateTime(record['in_time']);

      DateTime? recordDate = outDate ?? inDate;

      if (recordDate == null) continue;

      // inclusive range check
      if (!recordDate.isBefore(startDate) && !recordDate.isAfter(endDate)) {
        filteredRecords.add(record);
      }
    }

    return filteredRecords;
  }

  // UPDATED: Header page with accurate page numbers in report structure
  pw.Widget _buildHeaderPage({
    required String studentName,
    required String rollNo,
    required String hostel,
    required String currentMonth,
    required String previousMonth,
    required int currentYear,
    required int previousYear,
    required int currentMonthRecords,
    required int previousMonthRecords,
    required int currentMonthTablePages,
    required int previousMonthTablePages,
    required int currentDetailPages,
    required int previousDetailPages,
    required int currentPageNumber,
  }) {
    // Calculate page ranges
    // FIXED: Calculate page ranges with proper empty section handling
    final monthlyComparisonPage = 2;

    // Current month tables
    final currentMonthTablesStart = currentMonthTablePages > 0 ? monthlyComparisonPage + 1 : 0;
    final currentMonthTablesEnd = currentMonthTablePages > 0 
        ? currentMonthTablesStart + currentMonthTablePages - 1 
        : 0;

    // Previous month tables  
    final previousMonthTablesStart = (currentMonthTablePages > 0 && previousMonthTablePages > 0)
        ? currentMonthTablesEnd + 1
        : (previousMonthTablePages > 0 ? monthlyComparisonPage + 1 : 0);
    final previousMonthTablesEnd = previousMonthTablePages > 0 
        ? previousMonthTablesStart + previousMonthTablePages - 1 
        : 0;

    // Correct detail section starting pages
    final currentDetailsStart =
        monthlyComparisonPage +
        currentMonthTablePages +
        previousMonthTablePages + 1;

    final currentDetailsEnd = currentDetailPages > 0
        ? currentDetailsStart + currentDetailPages - 1
        : 0;

    // Previous month details start AFTER current month details
    final previousDetailsStart = currentDetailPages > 0
        ? currentDetailsEnd + 1
        : currentDetailsStart;

    final previousDetailsEnd = previousDetailPages > 0
        ? previousDetailsStart + previousDetailPages - 1
        : 0;


    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header with gradient background
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(30),
          decoration: pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [PdfColors.blue800, PdfColors.blue600],
            ),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                'STUDENT MOVEMENT ANALYSIS REPORT',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              pw.Text(
                'Two-Month Comparative Analysis',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontSize: 14,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ],
          ),
        ),
        
        pw.SizedBox(height: 40),
        
        // Student Information
        _buildInfoCard(
          title: 'STUDENT INFORMATION',
          items: [
            _buildInfoRow('Full Name', studentName),
            _buildInfoRow('Roll Number', rollNo),
            _buildInfoRow('Hostel', hostel),
          ],
        ),
        
        pw.SizedBox(height: 20),
        
        // Report Period Information
        _buildInfoCard(
          title: 'ANALYSIS PERIOD',
          items: [
            _buildInfoRow('Current Month', '$currentMonth $currentYear ($currentMonthRecords records)'),
            _buildInfoRow('Previous Month', '$previousMonth $previousYear ($previousMonthRecords records)'),
            _buildInfoRow('Report Generated', _formatDate(DateTime.now())),
            _buildInfoRow('Report Type', 'Two-Month Comparative Analysis'),
          ],
        ),
        
        pw.SizedBox(height: 30),
        
        // UPDATED: Report Structure Overview with accurate page numbers
        _buildInfoCard(
          title: 'REPORT STRUCTURE',
          items: [
            _buildInfoRow('Page $monthlyComparisonPage', 'Monthly Comparison Analysis'),
            if (currentMonthTablePages > 0)
              _buildInfoRow(
                'Pages ${_formatPageRange(currentMonthTablesStart, currentMonthTablesEnd)}', 
                'Daily Activity Breakdown - $currentMonth'
              ),
            if (previousMonthTablePages > 0)
              _buildInfoRow(
                'Pages ${_formatPageRange(previousMonthTablesStart, previousMonthTablesEnd)}', 
                'Daily Activity Breakdown - $previousMonth'
              ),
            if (currentDetailPages > 0)
              _buildInfoRow(
                'Pages ${_formatPageRange(currentDetailsStart, currentDetailsEnd)}', 
                'Detailed Movement Records - $currentMonth'
              ),
            if (previousDetailPages > 0)
              _buildInfoRow(
                'Pages ${_formatPageRange(previousDetailsStart, previousDetailsEnd)}', 
                'Detailed Movement Records - $previousMonth'
              ),
          ],
        ),
      ],
    );
  }

  // Helper method to format page ranges
  String _formatPageRange(int start, int end) {
    return start == end ? '$start' : '$start-$end';
  }

  // Monthly comparison page with reduced spacing to prevent overflow
  pw.Widget _buildMonthlyComparisonPage({
    required List<dynamic> currentMonthRecords,
    required List<dynamic> previousMonthRecords,
    required String currentMonth,
    required String previousMonth,
    required DateTime currentMonthStart,
    required DateTime currentMonthEnd,
    required DateTime previousMonthStart,
    required DateTime previousMonthEnd,
  }) {
    final currentStats = _calculateMonthlyStats(currentMonthRecords, currentMonthStart, currentMonthEnd);
    final previousStats = _calculateMonthlyStats(previousMonthRecords, previousMonthStart, previousMonthEnd);
    
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'MONTHLY COMPARISON ANALYSIS',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: primaryColor,
          ),
        ),
        pw.SizedBox(height: 10), 
        pw.Text(
          'Statistical Comparison: $currentMonth vs $previousMonth',
          style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 20), 
        
        // Current Month Statistics - COMPACT
        _buildCompactMonthlyStatsCard(
          monthName: currentMonth,
          stats: currentStats,
          color: PdfColors.blue500,
        ),
        
        pw.SizedBox(height: 20), 
        
        // Previous Month Statistics - COMPACT
        _buildCompactMonthlyStatsCard(
          monthName: previousMonth,
          stats: previousStats,
          color: PdfColors.green500,
        ),
        
        pw.SizedBox(height: 20), 
      ],
    );
  }

  // Compact monthly stats card to save space
  pw.Widget _buildCompactMonthlyStatsCard({
    required String monthName,
    required MonthlyStats stats,
    required PdfColor color,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20), 
      decoration: pw.BoxDecoration(
        color: _getPdfColorWithOpacity(color, 0.1),
        borderRadius: pw.BorderRadius.circular(10), 
        border: pw.Border.all(color: _getPdfColorWithOpacity(color, 0.3)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            monthName,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
          ),
          pw.SizedBox(height: 15), 
          _buildCompactInfoRow('Total Movements', stats.totalMovements.toString()),
          _buildCompactInfoRow('Check-Outs', stats.checkOuts.toString()),
          _buildCompactInfoRow('Check-Ins', stats.checkIns.toString()),
          _buildCompactInfoRow('Avg Time Outside', stats.avgTimeOutside),
          _buildCompactInfoRow('Longest Duration', stats.longestDuration),
          _buildCompactInfoRow('Most Active Day', stats.mostActiveDay),
          _buildCompactInfoRow('Peak Hour', stats.peakHour),
          _buildCompactInfoRow('Month Duration', stats.monthDuration),
        ],
      ),
    );
  }

  // Compact info row for monthly stats
  pw.Widget _buildCompactInfoRow(String label, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              '$label:',
              style: const pw.TextStyle(
                fontSize: 12, 
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 12), 
            ),
          ),
        ],
      ),
    );
  }

  // Widget builders
  pw.Widget _buildInfoCard({
    required String title,
    required List<pw.Widget> items,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.circular(10),
        border: pw.Border.all(color: PdfColors.grey300),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
              color: primaryColor,
            ),
          ),
          pw.SizedBox(height: 15),
          ...items,
        ],
      ),
    );
  }

  pw.Widget _buildInfoRow(String label, String value) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              '$label:',
              style: const pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700,
              ),
            ),
          ),
          pw.Expanded(
            flex: 3,
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Helper methods for monthly calculations
  MonthlyStats _calculateMonthlyStats(List<dynamic> records, DateTime monthStart, DateTime monthEnd) {
    final checkIns = records.where((r) => r['action'] == 'in').length;
    final checkOuts = records.where((r) => r['action'] == 'out').length;
    
    double totalTime = 0;
    int timeRecords = 0;
    double maxDuration = 0;
    
    final dayCount = <String, int>{};
    final hourCount = <int, int>{};
    
    for (var record in records) {
      final dateTime = _parseDateTime(record['out_time']);
      if (dateTime != null) {
        final day = _getDayOfWeek(dateTime.weekday);
        final hour = dateTime.hour;
        
        dayCount[day] = (dayCount[day] ?? 0) + 1;
        hourCount[hour] = (hourCount[hour] ?? 0) + 1;
      }
      
      if (record['time_spent_minutes'] != null) {
        final duration = double.tryParse(record['time_spent_minutes'].toString()) ?? 0;
        totalTime += duration;
        timeRecords++;
        if (duration > maxDuration) maxDuration = duration;
      }
    }
    
    final avgTime = timeRecords > 0 ? totalTime / timeRecords : 0;
    final mostActiveDay = dayCount.isNotEmpty 
        ? dayCount.entries.reduce((a, b) => a.value > b.value ? a : b).key 
        : 'No Activity';
        
    final peakHourEntry = hourCount.isNotEmpty 
        ? hourCount.entries.reduce((a, b) => a.value > b.value ? a : b)
        : null;
    final peakHour = peakHourEntry != null ? '${peakHourEntry.key}:00 (${peakHourEntry.value})' : 'No Activity';
    
    return MonthlyStats(
      totalMovements: records.length,
      checkIns: checkIns,
      checkOuts: checkOuts,
      avgTimeOutside: '${avgTime.toStringAsFixed(1)} min',
      longestDuration: '${maxDuration.toStringAsFixed(1)} min',
      mostActiveDay: mostActiveDay,
      peakHour: peakHour,
      monthDuration: _getMonthDuration(monthStart, monthEnd),
    );
  }

  /// Returns map: "DD/MM/YYYY" -> total minutes spent outside on that day (double, exact)
  Map<String, double> _calculateDailyTotalMinutes(
    DateTime monthStart,
    DateTime monthEnd,
    List<dynamic> records,
  ) {
    final dailyMinutes = <String, double>{};

    // Initialize all days of that month with 0.0
    var currentDay = DateTime(monthStart.year, monthStart.month, monthStart.day);
    while (currentDay.isBefore(monthEnd) || currentDay.isAtSameMomentAs(monthEnd)) {
      dailyMinutes[_formatDate(currentDay)] = 0.0;
      currentDay = currentDay.add(const Duration(days: 1));
    }

    for (var record in records) {
      try {
        final recordDate = _parseDateTime(record['out_time']);
        if (recordDate != null) {
          final dateKey = _formatDate(recordDate);
          if (!dailyMinutes.containsKey(dateKey)) {
            dailyMinutes[dateKey] = 0.0;
          }
          // Accumulate minutes if present; treat missing as 0
          final minutes = record['time_spent_minutes'] != null
              ? double.tryParse(record['time_spent_minutes'].toString()) ?? 0.0
              : 0.0;
          dailyMinutes[dateKey] = (dailyMinutes[dateKey] ?? 0.0) + minutes;
        }
      } catch (e) {
        print('⚠️ Error accumulating minutes for record: $e');
      }
    }

    return dailyMinutes;
  }

  Map<String, int> _calculateCompleteDailyBreakdown(
      DateTime monthStart,
      DateTime monthEnd,
      List<dynamic> records,
  ) {
    final dailyBreakdown = <String, int>{};

    // Initialize all days of that month with 0
    var currentDay = DateTime(monthStart.year, monthStart.month, monthStart.day);

    while (currentDay.isBefore(monthEnd) ||
        currentDay.isAtSameMomentAs(monthEnd)) {
      final dateKey = _formatDate(currentDay);
      dailyBreakdown[dateKey] = 0;
      currentDay = currentDay.add(const Duration(days: 1));
    }

    // Add actual movement records
    for (var record in records) {
      final recordDate = _parseDateTime(record['out_time']);
      if (recordDate != null) {
        final dateKey = _formatDate(recordDate);
        if (dailyBreakdown.containsKey(dateKey)) {
          dailyBreakdown[dateKey] = (dailyBreakdown[dateKey] ?? 0) + 1;
        }
      }
    }

    print('📊 Complete daily breakdown calculated: ${dailyBreakdown.length} days');
    return dailyBreakdown;
  }

  String _getMonthDuration(DateTime start, DateTime end) {
    final days = end.difference(start).inDays + 1;
    return '$days days';
  }

  // Helper method to handle PDF color opacity
  PdfColor _getPdfColorWithOpacity(PdfColor baseColor, double opacity) {
    return baseColor;
  }

  // Utility methods
  String _getMonthName(int month) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    final adjustedMonth = (month - 1) % 12;
    return months[adjustedMonth < 0 ? adjustedMonth + 12 : adjustedMonth];
  }

  String _getDayOfWeek(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Monday';
      case DateTime.tuesday:
        return 'Tuesday';
      case DateTime.wednesday:
        return 'Wednesday';
      case DateTime.thursday:
        return 'Thursday';
      case DateTime.friday:
        return 'Friday';
      case DateTime.saturday:
        return 'Saturday';
      case DateTime.sunday:
        return 'Sunday';
      default:
        return 'Unknown';
    }
  }

  // Improved date parsing with AM/PM support
  DateTime? _parseDateTime(dynamic dateTime) {
    try {
      if (dateTime == null) return null;
      
      if (dateTime is DateTime) {
        return dateTime;
      }
      
      if (dateTime is String) {
        // Handle DD/MM/YYYY HH:MM AM/PM format
        final ampmRegex = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4}) (\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false);
        final ampmMatch = ampmRegex.firstMatch(dateTime);
        if (ampmMatch != null) {
          try {
            final day = int.parse(ampmMatch.group(1)!);
            final month = int.parse(ampmMatch.group(2)!);
            final year = int.parse(ampmMatch.group(3)!);
            var hour = int.parse(ampmMatch.group(4)!);
            final minute = int.parse(ampmMatch.group(5)!);
            final period = ampmMatch.group(6)?.toUpperCase();

            // Handle 12-hour format
            if (period == 'PM' && hour < 12) hour += 12;
            if (period == 'AM' && hour == 12) hour = 0;

            // Validate date components
            if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
              return DateTime(year, month, day, hour, minute);
            }
          } catch (e) {
            print('⚠️ AM/PM date parsing failed: $e');
          }
        }
        
        // Handle format: "01/11/2025 00:00:00" (DD/MM/YYYY HH:MM:SS)
        if (dateTime.contains('/') && dateTime.contains(':')) {
          try {
            final parts = dateTime.split(' ');
            if (parts.length >= 1) {
              final datePart = parts[0];
              final dateParts = datePart.split('/');
              
              if (dateParts.length == 3) {
                final day = int.parse(dateParts[0]);
                final month = int.parse(dateParts[1]);
                final year = int.parse(dateParts[2]);
                
                int hour = 0, minute = 0, second = 0;
                if (parts.length >= 2) {
                  final timePart = parts[1];
                  final timeParts = timePart.split(':');
                  if (timeParts.length >= 3) {
                    hour = int.parse(timeParts[0]);
                    minute = int.parse(timeParts[1]);
                    second = int.parse(timeParts[2]);
                  }
                }
                
                return DateTime(year, month, day, hour, minute, second);
              }
            }
          } catch (e) {
            print('⚠️ DD/MM/YYYY parsing failed: $e');
          }
        }
        
        // Try ISO format
        try {
          return DateTime.parse(dateTime);
        } catch (e) {
          print('⚠️ ISO parsing failed: $e');
        }
        
        return null;
      }
      
      // Handle MongoDB format
      if (dateTime is Map && dateTime.containsKey('\$date')) {
        try {
          return DateTime.parse(dateTime['\$date']);
        } catch (e) {
          print('⚠️ MongoDB date parsing failed: $e');
        }
      }
      
      return null;
    } catch (e) {
      print('❌ Error parsing date: $dateTime, error: $e');
      return null;
    }
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    
    try {
      DateTime? date = _parseDateTime(dateTime);
      
      if (date != null) {
        return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
      }
      
      return dateTime.toString();
    } catch (e) {
      return dateTime.toString();
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatDuration(dynamic duration) {
    if (duration == null) return 'N/A';

    try {
      double minutes = duration is double
          ? duration
          : double.tryParse(duration.toString()) ?? 0.0;

      if (minutes >= 60) {
        double hours = minutes / 60;
        return '${hours.toStringAsFixed(2)} h';
      }

      return '${minutes.toStringAsFixed(2)} min';

    } catch (e) {
      return duration.toString();
    }
  }

  Future<String> _savePDF(pw.Document pdf, String fileName) async {
    try {
        final directory = await getTemporaryDirectory();
        final filePath = '${directory.path}/$fileName-${DateTime.now().millisecondsSinceEpoch}.pdf';
        
        print('💾 Saving PDF to: $filePath');
        
        final bytes = await pdf.save();
        await File(filePath).writeAsBytes(bytes);

        final file = File(filePath);
        final exists = await file.exists();
        
        if (!exists) {
        throw Exception('PDF file was not created');
        }

        final fileSize = await file.length();
        print('✅ PDF saved successfully at: $filePath (${fileSize} bytes)');
        
        return filePath;

    } catch (e) {
        print('❌ Error saving PDF: $e');
        throw Exception('Failed to save PDF: ${e.toString()}');
    }
  }

  // Memory management
  void dispose() {
    // Clear any cached data if needed
  }

  // Share PDF file
  Future<void> sharePDF(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await Share.shareXFiles([XFile(filePath)], text: 'Student Movement Analysis Report');
    }
  }
}
