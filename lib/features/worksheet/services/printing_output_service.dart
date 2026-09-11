import 'package:printing/printing.dart';

import '../../../core/utils/app_logger.dart';
import '../../../services/worksheet_pdf_service.dart';
import 'worksheet_preview_controller.dart';

/// The real print and share, through the `printing` plugin.
///
/// Both are handed the same bytes the preview was built from, so what comes out
/// of the printer is the document the teacher approved. Neither needs a
/// connection: the PDF is already in memory.
class PrintingOutputService implements WorksheetOutputService {
  const PrintingOutputService();

  @override
  Future<PrintingCapability> capability() async {
    try {
      final PrintingInfo info = await Printing.info();
      return PrintingCapability(
        canPrint: info.canPrint,
        canShare: info.canShare,
      );
    } on Object catch (error) {
      // No plugin, or a host with no print subsystem. Reported as unavailable
      // rather than offered and then failing under the teacher's hand.
      AppLogger.error('printing support could not be read', error: error);
      return const PrintingCapability.unknown();
    }
  }

  @override
  Future<bool> printPdf(WorksheetPdf pdf) => Printing.layoutPdf(
        name: pdf.fileName,
        onLayout: (_) async => pdf.bytes,
      );

  @override
  Future<bool> sharePdf(WorksheetPdf pdf) => Printing.sharePdf(
        bytes: pdf.bytes,
        filename: pdf.fileName,
      );
}
