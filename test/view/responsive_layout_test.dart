import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:laantech_pos_task/configs/utils/utils.dart';
import 'package:laantech_pos_task/configs/widgets/transfer/active_transfers_bar.dart';
import 'package:laantech_pos_task/model/server_file/server_file_model.dart';
import 'package:laantech_pos_task/model/transfer/network_health.dart';
import 'package:laantech_pos_task/model/transfer/transfer_task.dart';
import 'package:laantech_pos_task/model/user/session_model.dart';
import 'package:laantech_pos_task/repository/file_repository/file_repository.dart';
import 'package:laantech_pos_task/theme/app_theme.dart';
import 'package:laantech_pos_task/view/auth/login_view.dart';
import 'package:laantech_pos_task/view/auth/register_view.dart';
import 'package:laantech_pos_task/view/download/download_view.dart';
import 'package:laantech_pos_task/view/home/home_view.dart';
import 'package:laantech_pos_task/view/splash_screen/splash_view.dart';
import 'package:laantech_pos_task/view/transfers/transfer_details_view.dart';
import 'package:laantech_pos_task/view/transfers/transfers_view.dart';
import 'package:laantech_pos_task/view/upload/upload_view.dart';
import 'package:laantech_pos_task/view_model/auth_view_model/auth_view_model.dart';
import 'package:laantech_pos_task/view_model/server_files_view_model/server_files_view_model.dart';
import 'package:laantech_pos_task/view_model/transfer_view_model/transfer_view_model.dart';
import 'package:provider/provider.dart';

import '../helpers/fake_connectivity_service.dart';
import '../helpers/fake_transfer_repository.dart';
import '../helpers/fakes.dart';

/// Screen configurations covering small, medium and large Android phones,
/// different densities, a large text setting, landscape and a tablet.
const _screens = <String, ({Size size, double dpr, double text})>{
  'small phone 320x568 @2x': (size: Size(320, 568), dpr: 2, text: 1),
  'small phone, large text 1.3x': (size: Size(320, 568), dpr: 2, text: 1.3),
  'medium phone 393x852 @2.75x': (size: Size(393, 852), dpr: 2.75, text: 1),
  'large phone 430x932 @3x': (size: Size(430, 932), dpr: 3, text: 1),
  'large phone, large text 1.5x': (size: Size(430, 932), dpr: 3.5, text: 1.5),
  'landscape phone 852x393': (size: Size(852, 393), dpr: 2.75, text: 1),
  'landscape phone, large text 1.3x': (size: Size(852, 393), dpr: 2.75, text: 1.3),
  'small landscape 568x320': (size: Size(568, 320), dpr: 2, text: 1),
  'tablet 800x1280': (size: Size(800, 1280), dpr: 2, text: 1),
};

const _longName = 'Quarterly_product_catalog_with_all_store_branches_and_prices_2026_final_v3.mp4';

TransferTask _task(String id, {TransferType type = TransferType.upload, TransferStatus status = TransferStatus.running, NetworkHealth health = NetworkHealth.good, int speed = 0, String? error, String? server}) => TransferTask(
  id: id,
  type: type,
  fileName: '${id}_$_longName',
  localPath: '/storage/emulated/0/Download/LaanTech/${id}_$_longName',
  totalBytes: 734003200,
  transferredBytes: 587202560,
  status: status,
  createdAt: DateTime(2026, 11, 16, 10),
  updatedAt: DateTime(2026, 11, 16, 10, 5),
  serverFileName: server,
  error: error,
  networkHealth: health,
  bytesPerSecond: speed,
);

final _tasks = [
  _task('good', speed: 1536 * 1024),
  _task('poor', type: TransferType.download, health: NetworkHealth.poor, speed: 10 * 1024, server: 'poor.mp4'),
  _task('lost', health: NetworkHealth.offline),
  _task('reconnecting', type: TransferType.download, health: NetworkHealth.reconnecting, server: 'r.mp4'),
  _task('paused', type: TransferType.download, status: TransferStatus.paused, error: 'Paused: connection lost.', server: 'p.mp4'),
  _task('failed', status: TransferStatus.failed, error: 'The server rejected the file because it is larger than the allowed upload size for this account.'),
  _task('video', status: TransferStatus.completed, server: 'video_ab12.mp4'),
  _task('queued', status: TransferStatus.pending),
];

class _Files implements FileRepository {
  _Files(this.result);
  final Object result;

  @override
  Future<List<ServerFileModel>> fetchFiles() async => result is List<ServerFileModel> ? result as List<ServerFileModel> : throw result;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final _serverFiles = [
  for (final (i, type) in ['video/mp4', 'image/png', 'text/csv', 'application/pdf'].indexed)
    ServerFileModel(id: i, name: ['poor.mp4', 'r.mp4', 'p.mp4', 'x.pdf'][i], originalName: '${i}_$_longName', size: 734003200, type: type, uploadedAt: DateTime(2026, 11, 16, 9, 30), url: ''),
];

Future<void> _pump(WidgetTester tester, Widget screen, {List<TransferTask>? tasks}) async {
  final repository = FakeTransferRepository()..stored = tasks ?? _tasks;
  final auth = FakeAuthRepository()..session = SessionModel(token: 't', username: 'store_manager_downtown_branch_01', expiresAt: DateTime.now().add(const Duration(hours: 1)));
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel(repository: auth)..restoreSession()),
        ChangeNotifierProvider(create: (_) => TransferViewModel(repository: repository)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        // Same shell as the app: the persistent transfer bar under every screen.
        builder: (context, child) => Column(children: [Expanded(child: child!), const ActiveTransfersBar()]),
        home: screen,
        onGenerateRoute: (settings) => MaterialPageRoute(builder: (_) => const SizedBox()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

ServerFilesViewModel _filesVm(Object result) => ServerFilesViewModel(repository: _Files(result), connectivity: FakeConnectivityService(), retryDelays: const []);

final _cases = <String, Future<void> Function(WidgetTester)>{
  'splash': (t) => _pump(t, const SplashView()),
  'login': (t) => _pump(t, const LoginView()),
  'register': (t) => _pump(t, const RegisterView()),
  'home dashboard': (t) => _pump(t, const HomeView()),
  'upload with transfers': (t) => _pump(t, const UploadView()),
  'upload empty': (t) => _pump(t, const UploadView(), tasks: const []),
  'server files with downloads': (t) => _pump(t, DownloadView(createViewModel: () => _filesVm(_serverFiles))),
  'server files empty': (t) => _pump(t, DownloadView(createViewModel: () => _filesVm(<ServerFileModel>[]))),
  'server files error': (t) => _pump(t, DownloadView(createViewModel: () => _filesVm(Exception('No internet connection. The list will reload automatically when the connection is back.')))),
  'transfer center': (t) => _pump(t, const TransfersView()),
  'transfer details (running, network lost)': (t) => _pump(t, const TransferDetailsView(transferId: 'lost')),
  'transfer details (failed)': (t) => _pump(t, const TransferDetailsView(transferId: 'failed')),
  'transfer details (video)': (t) => _pump(t, const TransferDetailsView(transferId: 'video')),
  'confirm dialog': (t) async {
    await _pump(t, Builder(builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: () => Utils.confirm(context, title: 'Cancel upload of a very large catalog file?', message: 'The server does not support resuming uploads. Retrying later will start "$_longName" from the beginning.', confirmLabel: 'Cancel transfer', destructive: true), child: const Text('open'))))));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
  },
};

void main() {
  for (final screen in _screens.entries) {
    group(screen.key, () {
      for (final entry in _cases.entries) {
        testWidgets('${entry.key} lays out without overflow', (tester) async {
          tester.view.physicalSize = screen.value.size * screen.value.dpr;
          tester.view.devicePixelRatio = screen.value.dpr;
          tester.platformDispatcher.textScaleFactorTestValue = screen.value.text;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          // Any RenderFlex overflow is reported as a Flutter error, which fails
          // the test with the offending widget in the report.
          await entry.value(tester);
          expect(find.byType(Scaffold), findsWidgets);
          // Let the splash timer and similar delays finish cleanly.
          await tester.pump(const Duration(seconds: 3));
        });
      }
    });
  }
}
