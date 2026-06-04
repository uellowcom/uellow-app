// =============================================================================
// Tiny string translator. Avoids pulling flutter_localizations until we need
// the full intl package — for now, ~30 keys cover the static UI labels.
// =============================================================================
import '../../api/uellow_api.dart';

class T {
  T._();
  static const Map<String, Map<String, String>> _dict = {
    // Bottom nav
    'nav.home':       {'en': 'Home',    'ar': 'الرئيسية'},
    'nav.shop':       {'en': 'Shop',    'ar': 'المتجر'},
    'nav.cart':       {'en': 'Cart',    'ar': 'السلة'},
    'nav.account':    {'en': 'Account', 'ar': 'حسابي'},
    'nav.beena':      {'en': 'Beena',   'ar': 'بينا'},
    // Generic actions
    'action.continue':         {'en': 'Continue  →',          'ar': 'متابعة  →'},
    'action.continue_shop':    {'en': 'Continue shopping',    'ar': 'متابعة التسوق'},
    'action.cancel':           {'en': 'Cancel',               'ar': 'إلغاء'},
    'action.retry':            {'en': 'Retry',                'ar': 'إعادة المحاولة'},
    'action.save':             {'en': 'Save',                 'ar': 'حفظ'},
    'action.add_to_cart':      {'en': 'Add to cart',          'ar': 'أضف إلى السلة'},
    'action.buy_now':          {'en': 'Buy now',              'ar': 'اشترِ الآن'},
    'action.see_all':          {'en': 'See all →',            'ar': 'عرض الكل ←'},
    'action.see_more':         {'en': 'See more →',           'ar': 'المزيد ←'},
    'action.load_more':        {'en': 'Load more',            'ar': 'تحميل المزيد'},
    'action.checkout':         {'en': 'Secure Checkout',      'ar': 'إتمام الطلب الآمن'},
    // Cart
    'cart.empty.title':        {'en': 'Your cart is empty',       'ar': 'سلتك فارغة'},
    'cart.empty.subtitle':     {'en': 'Browse the latest deals and add to cart',
                                'ar': 'تصفح أحدث العروض وأضفها للسلة'},
    'cart.title':              {'en': 'My Cart',                  'ar': 'سلة التسوق'},
    'cart.items_count':        {'en': 'items · ready to checkout',
                                'ar': 'عناصر · جاهزة للطلب'},
    // Home
    'home.explore_more':       {'en': 'Explore More',             'ar': 'اكتشف المزيد'},
    'home.explore_subtitle':   {'en': 'for you',                  'ar': 'لك'},
    'home.end_feed':           {'en': '—  end of feed  —',        'ar': '— نهاية القائمة —'},
    // Search
    'search.placeholder':      {'en': 'Search products, brands, vendors…',
                                'ar': 'ابحث عن منتج، ماركة، أو تاجر…'},
    'search.recent':           {'en': 'RECENT SEARCHES',          'ar': 'عمليات البحث الأخيرة'},
    'search.trending':         {'en': 'TRENDING TODAY  🔥',       'ar': 'الأكثر بحثاً اليوم 🔥'},
    'search.browse_categories':{'en': 'BROWSE CATEGORIES',        'ar': 'تصفح الأقسام'},
    'search.clear_all':        {'en': 'Clear all',                'ar': 'حذف الكل'},
    // Splash
    'splash.title':            {'en': 'Choose where you\'re shopping from',
                                'ar': 'اختر بلد التسوق'},
    'splash.tagline':          {'en': 'Your trusted marketplace in the Middle East',
                                'ar': 'متجرك الموثوق في الشرق الأوسط'},
    // Brand
    'brand.official':          {'en': 'OFFICIAL BRAND',            'ar': 'علامة رسمية'},
    'brand.visit_store':       {'en': 'Browse more →',             'ar': 'تصفح المزيد ←'},
    // Account
    'account.sign_in':         {'en': 'Sign in',                   'ar': 'تسجيل الدخول'},
    'account.sign_out':        {'en': 'Sign out',                  'ar': 'تسجيل الخروج'},
    'account.email':           {'en': 'Email',                     'ar': 'البريد الإلكتروني'},
    'account.password':        {'en': 'Password',                  'ar': 'كلمة المرور'},
    'account.email_or_phone':  {'en': 'Email or phone',            'ar': 'البريد أو رقم الهاتف'},
    'account.name':            {'en': 'Full name',                 'ar': 'الاسم الكامل'},
    'account.phone':           {'en': 'Phone',                     'ar': 'رقم الهاتف'},
    'account.forgot':          {'en': 'Forgot password?',          'ar': 'نسيت كلمة المرور؟'},
    'account.remember':        {'en': 'Remember me',               'ar': 'تذكرني'},
    'account.create':          {'en': 'Create account  →',         'ar': 'إنشاء حساب  ←'},
    'account.create_short':    {'en': 'Create account',            'ar': 'إنشاء حساب'},
    'account.signin_arrow':    {'en': 'Sign in  →',                'ar': 'تسجيل الدخول  ←'},
    'account.or':              {'en': 'or continue with',          'ar': 'أو سجّل بـ'},
    'account.terms':           {'en': 'By continuing you agree to our Terms & Privacy.',
                                'ar': 'بمتابعتك فأنت توافق على الشروط والخصوصية.'},
    // Product page
    'product.description':     {'en': 'Description',               'ar': 'الوصف'},
    'product.specifications':  {'en': 'Specifications',            'ar': 'المواصفات'},
    'product.specs_subtitle':  {'en': 'Brand, materials, warranty & more',
                                'ar': 'الماركة، المواد، الضمان والمزيد'},
    'product.reviews':         {'en': 'Customer reviews',          'ar': 'تقييمات العملاء'},
    'product.related':         {'en': 'Related products',          'ar': 'منتجات مشابهة'},
    'product.bulk':            {'en': 'Bulk pricing',              'ar': 'تسعير الجملة'},
    'product.bulk_sub':        {'en': 'save more, buy more',       'ar': 'كلما زاد العدد، زاد التوفير'},
    'product.size':            {'en': 'Size',                      'ar': 'المقاس'},
    'product.color':           {'en': 'Color',                     'ar': 'اللون'},
    'product.write_review':    {'en': 'Write a review',            'ar': 'اكتب تقييم'},
    'product.deliver_to':      {'en': 'Deliver to',                'ar': 'التوصيل إلى'},
    'product.change_address':  {'en': 'Change address',            'ar': 'تغيير العنوان'},
    'product.notify_me':       {'en': 'Notify me when back in stock',
                                'ar': 'أعلمني عند توفر المنتج'},
    'product.add_cart':        {'en': 'Add to cart',               'ar': 'أضف إلى السلة'},
    'product.buy_now':         {'en': 'Buy now',                   'ar': 'اشترِ الآن'},
    'product.sold':            {'en': 'sold',                      'ar': 'تم بيعه'},
    'product.views':           {'en': 'views',                     'ar': 'مشاهدة'},
    'product.save_amount':     {'en': 'Save',                      'ar': 'وفّر'},
    // Reviews dialog
    'reviews.write':           {'en': 'Write a review',            'ar': 'اكتب تقييم'},
    'reviews.rating':          {'en': 'Your rating',               'ar': 'تقييمك'},
    'reviews.comment':         {'en': 'Your comment',              'ar': 'تعليقك'},
    'reviews.submit':          {'en': 'Submit review',             'ar': 'إرسال التقييم'},
    'reviews.no_reviews':      {'en': 'No reviews yet. Be the first to review this product.',
                                'ar': 'لا توجد تقييمات بعد. كن أول من يقيم هذا المنتج.'},
    'reviews.see_all':         {'en': 'See all reviews →',         'ar': 'عرض كل التقييمات ←'},
    'reviews.thanks':          {'en': 'Thanks for your review!',   'ar': 'شكراً على تقييمك!'},
    // Flash sale
    'flash.days':              {'en': 'DAYS',     'ar': 'أيام'},
    'flash.hours':             {'en': 'HOURS',    'ar': 'ساعات'},
    'flash.minutes':           {'en': 'MINUTES',  'ar': 'دقائق'},
    'flash.seconds':           {'en': 'SECONDS',  'ar': 'ثواني'},
    'flash.live':              {'en': '🔥 LIVE',     'ar': '🔥 الآن'},
    'flash.upcoming':          {'en': '⏰ UPCOMING', 'ar': '⏰ قريباً'},
    'flash.ended':             {'en': '🏁 ENDED',    'ar': '🏁 انتهت'},
    'flash.deals':             {'en': 'deals · in stock', 'ar': 'عرض · متوفر'},
    // Section subtitles
    'sec.flash_sub':           {'en': 'Up to 70% off — limited stock',
                                'ar': 'خصومات تصل إلى 70% — كميات محدودة'},
    'sec.brand_sub':           {'en': 'Officially partnered brand',
                                'ar': 'علامة تجارية رسمية معتمدة'},
    'sec.related_sub':         {'en': 'You may also like',
                                'ar': 'قد يعجبك أيضاً'},
    'sec.explore_sub':         {'en': 'Discover something new',
                                'ar': 'اكتشف شيئاً جديداً'},
  };

  /// Translate. Falls back to English if key missing in current lang.
  static String t(String key) {
    final lang = UellowApi.instance.lang;
    final entry = _dict[key];
    if (entry == null) return key;
    return entry[lang] ?? entry['en'] ?? key;
  }
}
