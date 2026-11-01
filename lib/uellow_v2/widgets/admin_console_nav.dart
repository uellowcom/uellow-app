// =============================================================================
// AdminConsoleNav — البار السفلي الموحّد لكونسول الإدارة (مطابق للموكاب):
//   الطلبات · سجل البوس · المنتجات · الدعم · المشتريات
// يظهر أسفل كل شاشات الكونسول. الضغط على تاب مختلف = pushReplacement لشاشته
// (تبديل تبويبات نظيف بدون تكويم الستاك). تاب «الدعم» عليه بادج أحمر بعدد
// رسائل الدعم غير المقروءة (helpdesk/unread).
// =============================================================================
import 'package:flutter/material.dart';

import '../../api/uellow_api.dart';
import '../screens/admin/admin_orders_screen.dart' as adm_orders;
import '../screens/admin/admin_pos_screen.dart' as adm_pos;
import '../screens/admin/admin_products_screen.dart' as adm_products;
import '../screens/admin/admin_purchase_screen.dart' as adm_purch;
import '../screens/admin/admin_customer_service_screen.dart' as adm_cs;

enum AdminTab { orders, pos, products, support, purchases }

class AdminConsoleNav extends StatefulWidget {
  const AdminConsoleNav({super.key, this.current});
  // null = لا تاب نشط (مثل رئيسية اللوحة/الإحصائيات).
  final AdminTab? current;

  @override
  State<AdminConsoleNav> createState() => _AdminConsoleNavState();
}

class _AdminConsoleNavState extends State<AdminConsoleNav> {
  int _supportUnread = 0;

  @override
  void initState() {
    super.initState();
    _loadSupport();
  }

  Future<void> _loadSupport() async {
    try {
      final res = await UellowApi.instance.getRaw(
          '/api/mobile/v2/helpdesk/unread', auth: true);
      final n = (res['data']?['unread'] as num?)?.toInt() ?? 0;
      if (mounted && n != _supportUnread) setState(() => _supportUnread = n);
    } catch (_) {}
  }

  void _go(AdminTab tab) {
    if (tab == widget.current) return;
    Widget screen;
    switch (tab) {
      case AdminTab.orders:
        screen = const adm_orders.AdminOrdersScreen();
        break;
      case AdminTab.pos:
        screen = const adm_pos.AdminPosScreen();
        break;
      case AdminTab.products:
        screen = const adm_products.AdminProductsScreen();
        break;
      case AdminTab.support:
        screen = const adm_cs.AdminCustomerServiceScreen();
        break;
      case AdminTab.purchases:
        screen = const adm_purch.AdminPurchaseScreen();
        break;
    }
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final ar = UellowApi.instance.lang == 'ar';
    const gold = Color(0xFFE8A800);
    const muted = Color(0xFF8F8774);
    final items = <_NavItemData>[
      _NavItemData(AdminTab.orders, Icons.list_alt_rounded,
          ar ? 'الطلبات' : 'Orders'),
      _NavItemData(AdminTab.pos, Icons.point_of_sale_rounded,
          ar ? 'سجل البوس' : 'POS Log'),
      _NavItemData(AdminTab.products, Icons.inventory_2_rounded,
          ar ? 'المنتجات' : 'Products'),
      _NavItemData(AdminTab.support, Icons.headset_mic_rounded,
          ar ? 'الدعم' : 'Support', badge: _supportUnread),
      _NavItemData(AdminTab.purchases, Icons.shopping_cart_rounded,
          ar ? 'المشتريات' : 'Purchases'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE9E1D1))),
        ),
        padding: const EdgeInsets.only(top: 7, bottom: 8),
        child: Row(
          children: [
            for (final it in items)
              Expanded(
                child: InkWell(
                  onTap: () => _go(it.tab),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Stack(clipBehavior: Clip.none, children: [
                        Icon(it.icon, size: 22,
                            color: it.tab == widget.current ? gold : muted),
                        if (it.badge > 0)
                          PositionedDirectional(
                            top: -4, end: -8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              constraints:
                                  const BoxConstraints(minWidth: 15, minHeight: 15),
                              decoration: BoxDecoration(
                                color: const Color(0xFFC23B2B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 1.2),
                              ),
                              alignment: Alignment.center,
                              child: Text(it.badge > 99 ? '99+' : '${it.badge}',
                                  style: const TextStyle(color: Colors.white,
                                      fontSize: 8.5, fontWeight: FontWeight.w900,
                                      height: 1.0)),
                            ),
                          ),
                      ]),
                      const SizedBox(height: 3),
                      Text(it.label,
                          style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w800,
                              color: it.tab == widget.current ? gold : muted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  _NavItemData(this.tab, this.icon, this.label, {this.badge = 0});
  final AdminTab tab;
  final IconData icon;
  final String label;
  final int badge;
}
