import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import 'home_screen.dart';
import 'profile_tab.dart';
import 'stats_tab.dart';

/// 主壳（v1.0.2）：底部三 Tab（首页/统计/我的）
/// IndexedStack 保活；切 Tab 回调刷新
/// （首页 refreshWeeklyStats、统计 StatsTabState.refresh）
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  final GlobalKey<StatsTabState> _statsKey = GlobalKey<StatsTabState>();

  @override
  Widget build(BuildContext context) {
    final appState = context.read<AppState>();
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          StatsTab(key: _statsKey),
          const ProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          if (i == _index) return;
          setState(() => _index = i);
          // 切 Tab 回调刷新
          if (i == 0) {
            appState.refreshWeeklyStats();
          } else if (i == 1) {
            _statsKey.currentState?.refresh();
          }
        },
        // v1.0.2 UI 设计稿：底部导航三 Tab（首页 🏠 / 统计 📊 / 我的 👤）
        destinations: const [
          NavigationDestination(
            icon: Text('🏠', style: TextStyle(fontSize: 20)),
            selectedIcon: Text('🏠', style: TextStyle(fontSize: 22)),
            label: '首页',
          ),
          NavigationDestination(
            icon: Text('📊', style: TextStyle(fontSize: 20)),
            selectedIcon: Text('📊', style: TextStyle(fontSize: 22)),
            label: '统计',
          ),
          NavigationDestination(
            icon: Text('👤', style: TextStyle(fontSize: 20)),
            selectedIcon: Text('👤', style: TextStyle(fontSize: 22)),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
