import 'package:flutter/material.dart';
import '../widgets/sidebar_menu.dart';
import 'dashboard/dashboard_page.dart';
import 'forecasting/forecasting_page.dart';
import 'settings/database_config_page.dart';

class MainLayoutScope extends InheritedWidget {
  final void Function(int index) switchPage;

  const MainLayoutScope({
    super.key,
    required this.switchPage,
    required super.child,
  });

  static MainLayoutScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MainLayoutScope>();
    assert(scope != null, 'No MainLayoutScope found in context');
    return scope!;
  }

  @override
  bool updateShouldNotify(MainLayoutScope oldWidget) => false;
}

class MainLayout extends StatefulWidget {
  final int initialIndex;
  const MainLayout({super.key, this.initialIndex = 0});

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  late int _currentIndex;

  final List<Widget> _pages = const [
    DashboardPage(),
    ForecastingPage(),
    DatabaseConfigPage(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  void _onMenuTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MainLayoutScope(
        switchPage: _onMenuTapped,
        child: Row(
          children: [
            // Fixed Sidebar on the left
            SidebarMenu(currentIndex: _currentIndex, onTap: _onMenuTapped),
            // Dynamic Page Content on the right — scrollable horizontally
            // so narrow windows scroll instead of overflow/break
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const double minWidth = 900;
                  final double width =
                      constraints.maxWidth < minWidth ? minWidth : constraints.maxWidth;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      height: constraints.maxHeight,
                      child: _pages[_currentIndex],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
