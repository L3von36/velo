import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_am.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('am'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'Velo'**
  String get appName;

  /// No description provided for @tagline.
  ///
  /// In en, this message translates to:
  /// **'Run your shop. Online or off.'**
  String get tagline;

  /// No description provided for @languageSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose your language'**
  String get languageSelectTitle;

  /// No description provided for @amharic.
  ///
  /// In en, this message translates to:
  /// **'አማርኛ'**
  String get amharic;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @login.
  ///
  /// In en, this message translates to:
  /// **'Log in'**
  String get login;

  /// No description provided for @welcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get welcomeBack;

  /// No description provided for @loginSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log in to manage your shop.'**
  String get loginSubtitle;

  /// No description provided for @itemsLowStock.
  ///
  /// In en, this message translates to:
  /// **'{n, plural, =1{1 item is low on stock} other{{n} items are low on stock}}'**
  String itemsLowStock(num n);

  /// No description provided for @searchItemsPlain.
  ///
  /// In en, this message translates to:
  /// **'Search items…'**
  String get searchItemsPlain;

  /// No description provided for @captureAgain.
  ///
  /// In en, this message translates to:
  /// **'Capture again'**
  String get captureAgain;

  /// No description provided for @location.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get location;

  /// No description provided for @notSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// No description provided for @signup.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get signup;

  /// No description provided for @phoneNumber.
  ///
  /// In en, this message translates to:
  /// **'Phone number'**
  String get phoneNumber;

  /// No description provided for @phoneHint.
  ///
  /// In en, this message translates to:
  /// **'+251 9XX XXX XXX'**
  String get phoneHint;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @confirmPassword.
  ///
  /// In en, this message translates to:
  /// **'Confirm password'**
  String get confirmPassword;

  /// No description provided for @forgotPassword.
  ///
  /// In en, this message translates to:
  /// **'Forgot password?'**
  String get forgotPassword;

  /// No description provided for @noAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account?'**
  String get noAccount;

  /// No description provided for @haveAccount.
  ///
  /// In en, this message translates to:
  /// **'Already have an account?'**
  String get haveAccount;

  /// No description provided for @createAccount.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get createAccount;

  /// No description provided for @fullName.
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get fullName;

  /// No description provided for @shopName.
  ///
  /// In en, this message translates to:
  /// **'Shop name'**
  String get shopName;

  /// No description provided for @terms.
  ///
  /// In en, this message translates to:
  /// **'I agree to the Terms of Service'**
  String get terms;

  /// No description provided for @wrongCredentials.
  ///
  /// In en, this message translates to:
  /// **'Wrong phone or password'**
  String get wrongCredentials;

  /// No description provided for @businessTypeTitle.
  ///
  /// In en, this message translates to:
  /// **'What kind of business?'**
  String get businessTypeTitle;

  /// No description provided for @businessTypeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This shapes your catalog, fields and modules — you can change it later in Settings.'**
  String get businessTypeSubtitle;

  /// No description provided for @branchSetupTitle.
  ///
  /// In en, this message translates to:
  /// **'Set up your first branch'**
  String get branchSetupTitle;

  /// No description provided for @branchName.
  ///
  /// In en, this message translates to:
  /// **'Branch name'**
  String get branchName;

  /// No description provided for @address.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get address;

  /// No description provided for @currencyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Currency & format'**
  String get currencyConfirmTitle;

  /// No description provided for @currencyConfirmNote.
  ///
  /// In en, this message translates to:
  /// **'Amounts are formatted in Ethiopian Birr. Sample:'**
  String get currencyConfirmNote;

  /// No description provided for @setupComplete.
  ///
  /// In en, this message translates to:
  /// **'You\'re all set!'**
  String get setupComplete;

  /// No description provided for @setupChecklist.
  ///
  /// In en, this message translates to:
  /// **'Setup checklist'**
  String get setupChecklist;

  /// No description provided for @goToDashboard.
  ///
  /// In en, this message translates to:
  /// **'Go to dashboard'**
  String get goToDashboard;

  /// No description provided for @addFirstItem.
  ///
  /// In en, this message translates to:
  /// **'Add your first item'**
  String get addFirstItem;

  /// No description provided for @skipForNow.
  ///
  /// In en, this message translates to:
  /// **'Skip for now'**
  String get skipForNow;

  /// No description provided for @home.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get home;

  /// No description provided for @sell.
  ///
  /// In en, this message translates to:
  /// **'Sell'**
  String get sell;

  /// No description provided for @catalog.
  ///
  /// In en, this message translates to:
  /// **'Catalog'**
  String get catalog;

  /// No description provided for @products.
  ///
  /// In en, this message translates to:
  /// **'Products'**
  String get products;

  /// No description provided for @services.
  ///
  /// In en, this message translates to:
  /// **'Services'**
  String get services;

  /// No description provided for @customers.
  ///
  /// In en, this message translates to:
  /// **'Customers'**
  String get customers;

  /// No description provided for @reports.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reports;

  /// No description provided for @staff.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staff;

  /// No description provided for @expenses.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenses;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @more.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @scanBarcode.
  ///
  /// In en, this message translates to:
  /// **'Scan barcode'**
  String get scanBarcode;

  /// No description provided for @scanHint.
  ///
  /// In en, this message translates to:
  /// **'Point the camera at a barcode'**
  String get scanHint;

  /// No description provided for @barcodeNotFound.
  ///
  /// In en, this message translates to:
  /// **'No item with this barcode'**
  String get barcodeNotFound;

  /// No description provided for @kindTitle.
  ///
  /// In en, this message translates to:
  /// **'What does your business sell?'**
  String get kindTitle;

  /// No description provided for @kindSubtitle.
  ///
  /// In en, this message translates to:
  /// **'This shapes your catalog, POS and reports.'**
  String get kindSubtitle;

  /// No description provided for @kindBoth.
  ///
  /// In en, this message translates to:
  /// **'Products & services'**
  String get kindBoth;

  /// No description provided for @kindProductsSub.
  ///
  /// In en, this message translates to:
  /// **'Stock items, prices and inventory'**
  String get kindProductsSub;

  /// No description provided for @kindServicesSub.
  ///
  /// In en, this message translates to:
  /// **'Appointments and billable work'**
  String get kindServicesSub;

  /// No description provided for @kindBothSub.
  ///
  /// In en, this message translates to:
  /// **'A mix of both — hybrid shops'**
  String get kindBothSub;

  /// No description provided for @locationTitle.
  ///
  /// In en, this message translates to:
  /// **'Where is your shop?'**
  String get locationTitle;

  /// No description provided for @locationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Capture your GPS location or type the area — used on records and receipts.'**
  String get locationSubtitle;

  /// No description provided for @useMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my current location'**
  String get useMyLocation;

  /// No description provided for @locationCaptured.
  ///
  /// In en, this message translates to:
  /// **'Location captured'**
  String get locationCaptured;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location unavailable — you can type the address instead'**
  String get locationDenied;

  /// No description provided for @locating.
  ///
  /// In en, this message translates to:
  /// **'Locating…'**
  String get locating;

  /// No description provided for @appointments.
  ///
  /// In en, this message translates to:
  /// **'Appointments'**
  String get appointments;

  /// No description provided for @dashboard.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get dashboard;

  /// No description provided for @todaySales.
  ///
  /// In en, this message translates to:
  /// **'Today\'s sales'**
  String get todaySales;

  /// No description provided for @vsYesterday.
  ///
  /// In en, this message translates to:
  /// **'vs yesterday'**
  String get vsYesterday;

  /// No description provided for @weekSales.
  ///
  /// In en, this message translates to:
  /// **'This week'**
  String get weekSales;

  /// No description provided for @lowStock.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStock;

  /// No description provided for @topItemsToday.
  ///
  /// In en, this message translates to:
  /// **'Top items today'**
  String get topItemsToday;

  /// No description provided for @quickActions.
  ///
  /// In en, this message translates to:
  /// **'Quick actions'**
  String get quickActions;

  /// No description provided for @newSale.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get newSale;

  /// No description provided for @addItem.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItem;

  /// No description provided for @viewReports.
  ///
  /// In en, this message translates to:
  /// **'View reports'**
  String get viewReports;

  /// No description provided for @noSalesYet.
  ///
  /// In en, this message translates to:
  /// **'No sales yet today'**
  String get noSalesYet;

  /// No description provided for @startSelling.
  ///
  /// In en, this message translates to:
  /// **'Start selling'**
  String get startSelling;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchItems.
  ///
  /// In en, this message translates to:
  /// **'Search items or scan barcode…'**
  String get searchItems;

  /// No description provided for @cart.
  ///
  /// In en, this message translates to:
  /// **'Cart'**
  String get cart;

  /// No description provided for @cartEmpty.
  ///
  /// In en, this message translates to:
  /// **'Cart is empty'**
  String get cartEmpty;

  /// No description provided for @subtotal.
  ///
  /// In en, this message translates to:
  /// **'Subtotal'**
  String get subtotal;

  /// No description provided for @discount.
  ///
  /// In en, this message translates to:
  /// **'Discount'**
  String get discount;

  /// No description provided for @tax.
  ///
  /// In en, this message translates to:
  /// **'Tax'**
  String get tax;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @charge.
  ///
  /// In en, this message translates to:
  /// **'Charge'**
  String get charge;

  /// No description provided for @walkIn.
  ///
  /// In en, this message translates to:
  /// **'Walk-in'**
  String get walkIn;

  /// No description provided for @attachCustomer.
  ///
  /// In en, this message translates to:
  /// **'Attach customer'**
  String get attachCustomer;

  /// No description provided for @clearCart.
  ///
  /// In en, this message translates to:
  /// **'Clear cart'**
  String get clearCart;

  /// No description provided for @holdSale.
  ///
  /// In en, this message translates to:
  /// **'Hold sale'**
  String get holdSale;

  /// No description provided for @heldSales.
  ///
  /// In en, this message translates to:
  /// **'Held sales'**
  String get heldSales;

  /// No description provided for @resumeSale.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeSale;

  /// No description provided for @paymentMethod.
  ///
  /// In en, this message translates to:
  /// **'Payment method'**
  String get paymentMethod;

  /// No description provided for @cash.
  ///
  /// In en, this message translates to:
  /// **'Cash'**
  String get cash;

  /// No description provided for @telebirr.
  ///
  /// In en, this message translates to:
  /// **'Telebirr'**
  String get telebirr;

  /// No description provided for @cbe.
  ///
  /// In en, this message translates to:
  /// **'CBE Birr'**
  String get cbe;

  /// No description provided for @credit.
  ///
  /// In en, this message translates to:
  /// **'On credit'**
  String get credit;

  /// No description provided for @amountDue.
  ///
  /// In en, this message translates to:
  /// **'Amount due'**
  String get amountDue;

  /// No description provided for @amountTendered.
  ///
  /// In en, this message translates to:
  /// **'Amount tendered'**
  String get amountTendered;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @completeSale.
  ///
  /// In en, this message translates to:
  /// **'Complete sale'**
  String get completeSale;

  /// No description provided for @referenceNumber.
  ///
  /// In en, this message translates to:
  /// **'Reference / transaction number'**
  String get referenceNumber;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @markPaidManually.
  ///
  /// In en, this message translates to:
  /// **'Mark as paid manually'**
  String get markPaidManually;

  /// No description provided for @pendingVerification.
  ///
  /// In en, this message translates to:
  /// **'Pending verification'**
  String get pendingVerification;

  /// No description provided for @verified.
  ///
  /// In en, this message translates to:
  /// **'Verified'**
  String get verified;

  /// No description provided for @creditRequiresCustomer.
  ///
  /// In en, this message translates to:
  /// **'Attach a customer to sell on credit'**
  String get creditRequiresCustomer;

  /// No description provided for @saleComplete.
  ///
  /// In en, this message translates to:
  /// **'Sale complete'**
  String get saleComplete;

  /// No description provided for @receipt.
  ///
  /// In en, this message translates to:
  /// **'Receipt'**
  String get receipt;

  /// No description provided for @newSaleBtn.
  ///
  /// In en, this message translates to:
  /// **'New sale'**
  String get newSaleBtn;

  /// No description provided for @outOfStock.
  ///
  /// In en, this message translates to:
  /// **'Out of stock'**
  String get outOfStock;

  /// No description provided for @qty.
  ///
  /// In en, this message translates to:
  /// **'Qty'**
  String get qty;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @uncategorized.
  ///
  /// In en, this message translates to:
  /// **'Uncategorized'**
  String get uncategorized;

  /// No description provided for @categories.
  ///
  /// In en, this message translates to:
  /// **'Categories'**
  String get categories;

  /// No description provided for @addItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Add item'**
  String get addItemTitle;

  /// No description provided for @editItem.
  ///
  /// In en, this message translates to:
  /// **'Edit item'**
  String get editItem;

  /// No description provided for @addProduct.
  ///
  /// In en, this message translates to:
  /// **'Add product'**
  String get addProduct;

  /// No description provided for @addService.
  ///
  /// In en, this message translates to:
  /// **'Add service'**
  String get addService;

  /// No description provided for @price.
  ///
  /// In en, this message translates to:
  /// **'Price'**
  String get price;

  /// No description provided for @cost.
  ///
  /// In en, this message translates to:
  /// **'Cost'**
  String get cost;

  /// No description provided for @costHint.
  ///
  /// In en, this message translates to:
  /// **'Add cost to see real profit in reports'**
  String get costHint;

  /// No description provided for @stockQty.
  ///
  /// In en, this message translates to:
  /// **'Stock quantity'**
  String get stockQty;

  /// No description provided for @lowStockThreshold.
  ///
  /// In en, this message translates to:
  /// **'Low-stock alert at'**
  String get lowStockThreshold;

  /// No description provided for @barcode.
  ///
  /// In en, this message translates to:
  /// **'Barcode / SKU'**
  String get barcode;

  /// No description provided for @unit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get unit;

  /// No description provided for @duration.
  ///
  /// In en, this message translates to:
  /// **'Duration (minutes)'**
  String get duration;

  /// No description provided for @category.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get category;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get edit;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @name.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get name;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @hasVariants.
  ///
  /// In en, this message translates to:
  /// **'This item has variants (size, color…)'**
  String get hasVariants;

  /// No description provided for @variants.
  ///
  /// In en, this message translates to:
  /// **'Variants'**
  String get variants;

  /// No description provided for @stockHistory.
  ///
  /// In en, this message translates to:
  /// **'Stock history'**
  String get stockHistory;

  /// No description provided for @salesHistory.
  ///
  /// In en, this message translates to:
  /// **'Sales history'**
  String get salesHistory;

  /// No description provided for @salesHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Sales history'**
  String get salesHistoryTitle;

  /// No description provided for @lowStockList.
  ///
  /// In en, this message translates to:
  /// **'Low stock'**
  String get lowStockList;

  /// No description provided for @allStockedUp.
  ///
  /// In en, this message translates to:
  /// **'All stocked up!'**
  String get allStockedUp;

  /// No description provided for @stockAdjust.
  ///
  /// In en, this message translates to:
  /// **'Adjust stock'**
  String get stockAdjust;

  /// No description provided for @newQty.
  ///
  /// In en, this message translates to:
  /// **'New quantity'**
  String get newQty;

  /// No description provided for @reason.
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get reason;

  /// No description provided for @damaged.
  ///
  /// In en, this message translates to:
  /// **'Damaged'**
  String get damaged;

  /// No description provided for @lost.
  ///
  /// In en, this message translates to:
  /// **'Lost'**
  String get lost;

  /// No description provided for @miscount.
  ///
  /// In en, this message translates to:
  /// **'Miscount'**
  String get miscount;

  /// No description provided for @other.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get other;

  /// No description provided for @customerName.
  ///
  /// In en, this message translates to:
  /// **'Customer name'**
  String get customerName;

  /// No description provided for @addCustomer.
  ///
  /// In en, this message translates to:
  /// **'Add customer'**
  String get addCustomer;

  /// No description provided for @balance.
  ///
  /// In en, this message translates to:
  /// **'Balance'**
  String get balance;

  /// No description provided for @recordPayment.
  ///
  /// In en, this message translates to:
  /// **'Record payment'**
  String get recordPayment;

  /// No description provided for @recordCharge.
  ///
  /// In en, this message translates to:
  /// **'Record charge'**
  String get recordCharge;

  /// No description provided for @ledger.
  ///
  /// In en, this message translates to:
  /// **'Debt ledger'**
  String get ledger;

  /// No description provided for @purchaseHistory.
  ///
  /// In en, this message translates to:
  /// **'Purchase history'**
  String get purchaseHistory;

  /// No description provided for @newSaleForCustomer.
  ///
  /// In en, this message translates to:
  /// **'New sale for this customer'**
  String get newSaleForCustomer;

  /// No description provided for @debtors.
  ///
  /// In en, this message translates to:
  /// **'Debtors'**
  String get debtors;

  /// No description provided for @noOutstandingDebt.
  ///
  /// In en, this message translates to:
  /// **'No outstanding debt!'**
  String get noOutstandingDebt;

  /// No description provided for @staffList.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffList;

  /// No description provided for @addStaff.
  ///
  /// In en, this message translates to:
  /// **'Add staff'**
  String get addStaff;

  /// No description provided for @role.
  ///
  /// In en, this message translates to:
  /// **'Role'**
  String get role;

  /// No description provided for @owner.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get owner;

  /// No description provided for @manager.
  ///
  /// In en, this message translates to:
  /// **'Manager'**
  String get manager;

  /// No description provided for @cashierRole.
  ///
  /// In en, this message translates to:
  /// **'Cashier'**
  String get cashierRole;

  /// No description provided for @staffRole.
  ///
  /// In en, this message translates to:
  /// **'Staff'**
  String get staffRole;

  /// No description provided for @branch.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get branch;

  /// No description provided for @commission.
  ///
  /// In en, this message translates to:
  /// **'Commission %'**
  String get commission;

  /// No description provided for @active.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @addExpense.
  ///
  /// In en, this message translates to:
  /// **'Add expense'**
  String get addExpense;

  /// No description provided for @expenseCategories.
  ///
  /// In en, this message translates to:
  /// **'Expense categories'**
  String get expenseCategories;

  /// No description provided for @amount.
  ///
  /// In en, this message translates to:
  /// **'Amount'**
  String get amount;

  /// No description provided for @note.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get note;

  /// No description provided for @date.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get date;

  /// No description provided for @salesReport.
  ///
  /// In en, this message translates to:
  /// **'Sales'**
  String get salesReport;

  /// No description provided for @bestSellers.
  ///
  /// In en, this message translates to:
  /// **'Best sellers'**
  String get bestSellers;

  /// No description provided for @staffPerformance.
  ///
  /// In en, this message translates to:
  /// **'Staff performance'**
  String get staffPerformance;

  /// No description provided for @profitLoss.
  ///
  /// In en, this message translates to:
  /// **'Profit & loss'**
  String get profitLoss;

  /// No description provided for @inventoryValue.
  ///
  /// In en, this message translates to:
  /// **'Inventory value'**
  String get inventoryValue;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @week.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get week;

  /// No description provided for @month.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get month;

  /// No description provided for @custom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get custom;

  /// No description provided for @revenue.
  ///
  /// In en, this message translates to:
  /// **'Revenue'**
  String get revenue;

  /// No description provided for @cogs.
  ///
  /// In en, this message translates to:
  /// **'Cost of goods'**
  String get cogs;

  /// No description provided for @grossProfit.
  ///
  /// In en, this message translates to:
  /// **'Gross profit'**
  String get grossProfit;

  /// No description provided for @expenseTotal.
  ///
  /// In en, this message translates to:
  /// **'Expenses'**
  String get expenseTotal;

  /// No description provided for @netProfit.
  ///
  /// In en, this message translates to:
  /// **'Net profit'**
  String get netProfit;

  /// No description provided for @pnlWarning.
  ///
  /// In en, this message translates to:
  /// **'Estimate — some products have no cost recorded.'**
  String get pnlWarning;

  /// No description provided for @averageSale.
  ///
  /// In en, this message translates to:
  /// **'Average sale'**
  String get averageSale;

  /// No description provided for @transactions.
  ///
  /// In en, this message translates to:
  /// **'Transactions'**
  String get transactions;

  /// No description provided for @byMethod.
  ///
  /// In en, this message translates to:
  /// **'By payment method'**
  String get byMethod;

  /// No description provided for @byStaff.
  ///
  /// In en, this message translates to:
  /// **'By staff'**
  String get byStaff;

  /// No description provided for @businessProfile.
  ///
  /// In en, this message translates to:
  /// **'Business profile'**
  String get businessProfile;

  /// No description provided for @paymentSetup.
  ///
  /// In en, this message translates to:
  /// **'Payment methods'**
  String get paymentSetup;

  /// No description provided for @telebirrNumber.
  ///
  /// In en, this message translates to:
  /// **'Telebirr number'**
  String get telebirrNumber;

  /// No description provided for @cbeNumber.
  ///
  /// In en, this message translates to:
  /// **'CBE account'**
  String get cbeNumber;

  /// No description provided for @receiptSettings.
  ///
  /// In en, this message translates to:
  /// **'Receipt settings'**
  String get receiptSettings;

  /// No description provided for @receiptFooter.
  ///
  /// In en, this message translates to:
  /// **'Receipt footer message'**
  String get receiptFooter;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @plan.
  ///
  /// In en, this message translates to:
  /// **'Subscription plan'**
  String get plan;

  /// No description provided for @free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get free;

  /// No description provided for @basic.
  ///
  /// In en, this message translates to:
  /// **'Basic'**
  String get basic;

  /// No description provided for @pro.
  ///
  /// In en, this message translates to:
  /// **'Pro'**
  String get pro;

  /// No description provided for @businessType.
  ///
  /// In en, this message translates to:
  /// **'Business type'**
  String get businessType;

  /// No description provided for @logout.
  ///
  /// In en, this message translates to:
  /// **'Log out'**
  String get logout;

  /// No description provided for @synced.
  ///
  /// In en, this message translates to:
  /// **'All changes synced'**
  String get synced;

  /// No description provided for @offlineBanner.
  ///
  /// In en, this message translates to:
  /// **'Offline — sales still work, data syncs when back online'**
  String get offlineBanner;

  /// No description provided for @emptyCatalog.
  ///
  /// In en, this message translates to:
  /// **'Your catalog is empty'**
  String get emptyCatalog;

  /// No description provided for @emptyCatalogHint.
  ///
  /// In en, this message translates to:
  /// **'Add your first product or service to start selling'**
  String get emptyCatalogHint;

  /// No description provided for @emptyCustomers.
  ///
  /// In en, this message translates to:
  /// **'No customers yet'**
  String get emptyCustomers;

  /// No description provided for @emptyCustomersHint.
  ///
  /// In en, this message translates to:
  /// **'Customers you serve will appear here'**
  String get emptyCustomersHint;

  /// No description provided for @emptySales.
  ///
  /// In en, this message translates to:
  /// **'No sales in this period'**
  String get emptySales;

  /// No description provided for @emptyExpenses.
  ///
  /// In en, this message translates to:
  /// **'No expenses recorded'**
  String get emptyExpenses;

  /// No description provided for @emptyHeld.
  ///
  /// In en, this message translates to:
  /// **'No held sales'**
  String get emptyHeld;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @errorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get errorGeneric;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @stockUpdated.
  ///
  /// In en, this message translates to:
  /// **'Stock updated'**
  String get stockUpdated;

  /// No description provided for @mySalesToday.
  ///
  /// In en, this message translates to:
  /// **'My sales today'**
  String get mySalesToday;

  /// No description provided for @myAppointmentsToday.
  ///
  /// In en, this message translates to:
  /// **'My appointments today'**
  String get myAppointmentsToday;

  /// No description provided for @saleRefund.
  ///
  /// In en, this message translates to:
  /// **'Refund'**
  String get saleRefund;

  /// No description provided for @refundConfirm.
  ///
  /// In en, this message translates to:
  /// **'Refund this sale? Stock will be restored and the sale marked as refunded.'**
  String get refundConfirm;

  /// No description provided for @refunded.
  ///
  /// In en, this message translates to:
  /// **'Refunded'**
  String get refunded;

  /// No description provided for @walkInCustomer.
  ///
  /// In en, this message translates to:
  /// **'Walk-in customer'**
  String get walkInCustomer;

  /// No description provided for @items.
  ///
  /// In en, this message translates to:
  /// **'items'**
  String get items;

  /// No description provided for @demoAccounts.
  ///
  /// In en, this message translates to:
  /// **'Demo accounts (tap to fill)'**
  String get demoAccounts;

  /// No description provided for @serverUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverUrl;

  /// No description provided for @serverUrlHint.
  ///
  /// In en, this message translates to:
  /// **'For native builds: your backend address'**
  String get serverUrlHint;

  /// No description provided for @darkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark mode'**
  String get darkMode;

  /// No description provided for @pickLocation.
  ///
  /// In en, this message translates to:
  /// **'Set shop location'**
  String get pickLocation;

  /// No description provided for @mapHint.
  ///
  /// In en, this message translates to:
  /// **'Drag the map to position the pin'**
  String get mapHint;

  /// No description provided for @saveLocation.
  ///
  /// In en, this message translates to:
  /// **'Save location'**
  String get saveLocation;

  /// No description provided for @detectAddress.
  ///
  /// In en, this message translates to:
  /// **'Detect address here'**
  String get detectAddress;

  /// No description provided for @detectFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t detect the address — you can still save the pin.'**
  String get detectFailed;

  /// No description provided for @pickOnMap.
  ///
  /// In en, this message translates to:
  /// **'Pick on map'**
  String get pickOnMap;

  /// No description provided for @taxId.
  ///
  /// In en, this message translates to:
  /// **'Tax ID (TIN)'**
  String get taxId;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['am', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'am':
      return AppLocalizationsAm();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
