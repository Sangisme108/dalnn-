import 'package:flutter/material.dart';

enum RoleBottomTab {
  home,
  employees,
  scan,
  invoices,
  confirmOrders,
  offers,
  cart,
  orders,
  account,
}

class RoleBottomNavigationBar extends StatelessWidget {
  final String role;
  final RoleBottomTab currentTab;
  final ValueChanged<RoleBottomTab> onTabSelected;

  const RoleBottomNavigationBar({
    super.key,
    required this.role,
    required this.currentTab,
    required this.onTabSelected,
  });

  static const Color _activeColor = Color(0xFF2563EB);
  static const Color _inactiveColor = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    if (role == 'admin') return _employeeBar();
    if (role == 'employee') return _employeeBar();
    if (role == 'customer') return _customerBar();
    return const SizedBox.shrink();
  }

  Widget _employeeBar() {
    return _BarShell(
      child: SizedBox(
        height: 86,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: [
            Row(
              children: [
                Expanded(
                  child: _employeeNavItem(
                    tab: RoleBottomTab.home,
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    label: 'Home',
                  ),
                ),
                Expanded(
                  child: _employeeNavItem(
                    tab: RoleBottomTab.cart,
                    icon: Icons.shopping_cart_outlined,
                    activeIcon: Icons.shopping_cart,
                    label: 'Thanh toán',
                  ),
                ),
                const SizedBox(width: 90),
                Expanded(
                  child: _employeeNavItem(
                    tab: RoleBottomTab.confirmOrders,
                    icon: Icons.assignment_turned_in_outlined,
                    activeIcon: Icons.assignment_turned_in,
                    label: 'Xác nhận đơn',
                  ),
                ),
                Expanded(
                  child: _employeeNavItem(
                    tab: RoleBottomTab.account,
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    label: 'Tài khoản',
                  ),
                ),
              ],
            ),
            Positioned(
              top: -24,
              child: GestureDetector(
                onTap: () => onTabSelected(RoleBottomTab.scan),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                        ),
                        border: Border.all(color: Colors.white, width: 5),
                        boxShadow: [
                          BoxShadow(
                            color: _activeColor.withOpacity(0.34),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Quét mã',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: currentTab == RoleBottomTab.scan
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: currentTab == RoleBottomTab.scan
                            ? _activeColor
                            : _inactiveColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _customerBar() {
    final tabs = [
      _TabData(RoleBottomTab.home, Icons.home_outlined, Icons.home, 'Home'),
      _TabData(
        RoleBottomTab.offers,
        Icons.local_offer_outlined,
        Icons.local_offer,
        'Ưu đãi',
      ),
      _TabData(
        RoleBottomTab.cart,
        Icons.shopping_cart_outlined,
        Icons.shopping_cart,
        'Giỏ hàng',
      ),
      _TabData(
        RoleBottomTab.orders,
        Icons.receipt_long_outlined,
        Icons.receipt_long,
        'Đơn hàng',
      ),
      _TabData(
        RoleBottomTab.account,
        Icons.person_outline,
        Icons.person,
        'Tài khoản',
      ),
    ];

    return _BarShell(child: _bottomBar(tabs));
  }

  BottomNavigationBar _bottomBar(List<_TabData> tabs) {
    final index = tabs.indexWhere((tab) => tab.tab == currentTab);
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: index < 0 ? 0 : index,
      selectedItemColor: _activeColor,
      unselectedItemColor: _inactiveColor,
      selectedFontSize: 12,
      unselectedFontSize: 12,
      showUnselectedLabels: true,
      elevation: 0,
      backgroundColor: Colors.white,
      onTap: (index) => onTabSelected(tabs[index].tab),
      items: tabs
          .map(
            (tab) => BottomNavigationBarItem(
              icon: Icon(tab.icon),
              activeIcon: Icon(tab.activeIcon),
              label: tab.label,
            ),
          )
          .toList(),
    );
  }

  Widget _employeeNavItem({
    required RoleBottomTab tab,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = currentTab == tab;
    return InkResponse(
      onTap: () => onTabSelected(tab),
      radius: 28,
      child: Padding(
        padding: const EdgeInsets.only(top: 9),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? _activeColor : _inactiveColor,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                color: isActive ? _activeColor : _inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarShell extends StatelessWidget {
  final Widget child;

  const _BarShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _TabData {
  final RoleBottomTab tab;
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const _TabData(this.tab, this.icon, this.activeIcon, this.label);
}
