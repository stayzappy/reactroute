import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart'; 
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;
import 'package:webthree/webthree.dart' as web3;
import 'package:webthree/crypto.dart' as web3_crypto;
import 'package:convert/convert.dart';

// ==============================================================
// 1. STRICT JS INTEROP DEFINITIONS (EVM Injected Wallets)
// ==============================================================
@JS('window.ethereum')
external Ethereum? get ethereum;

@JS('window.coinbaseWalletExtension')
external Ethereum? get coinbaseWalletExtension;

@JS('window.trustwallet')
external Ethereum? get trustWallet;

@JS('window.phantom.ethereum')
external Ethereum? get phantomWallet;

@JS()
extension type Ethereum._(JSObject _) implements JSObject {
  external JSPromise request(RequestArguments args);
  external bool? get isMetaMask;
  external bool? get isRabby;
  external bool? get isCoinbaseWallet;
  external bool? get isTrust;
  external bool? get isPhantom;
}

@JS()
@anonymous
extension type RequestArguments._(JSObject _) implements JSObject {
  external factory RequestArguments({
    required JSString method,
    JSAny? params,
  });
}

// ==============================================================
// 2. DATA MODELS & UTILS
// ==============================================================
class AffiliateStat {
  final String address;
  final BigInt earnings;
  AffiliateStat(this.address, this.earnings);
}

class CampaignData {
  final int id;
  final String marketer;
  final String targetContract;
  final int rewardType;
  final BigInt rewardValue;
  final BigInt budgetRemaining;
  final bool isActive;
  final BigInt totalPayouts;
  final BigInt totalConversions;
  final List<AffiliateStat> affiliates;

  CampaignData({
    required this.id, required this.marketer, required this.targetContract,
    required this.rewardType, required this.rewardValue,
    required this.budgetRemaining, required this.isActive,
    required this.totalPayouts, required this.totalConversions,
    required this.affiliates
  });
}

Map<String, String> parseWebUrlParams() {
  final url = web.window.location.href;
  final uri = Uri.parse(url);
  final params = <String, String>{};
  params.addAll(uri.queryParameters);
  if (uri.hasFragment && uri.fragment.contains('?')) {
    final fragmentQuery = uri.fragment.substring(uri.fragment.indexOf('?'));
    final fragUri = Uri.parse(fragmentQuery);
    params.addAll(fragUri.queryParameters);
  }
  return params;
}

// ==============================================================
// 3. WEB3 ABI SERVICE (Network Aware & Telemetry Added)
// ==============================================================
class Web3Service {
  // === BRAND NEW ARCHITECTURE ADDRESSES INJECTED ===
  static const String testnetManager = "0xaA613D99fDD40A749153B3cDc0B95e7101bfc6f0"; 
  static const String testnetMarket = "0x4946E7761b8c896FA6F39eDcf7aB13A7eF79835e";  

  static const String mainnetManager = "0x00..."; 
  static const String mainnetMarket = "0x00...";  

  static String getManagerAddress(String chainId) => chainId == '0xc487' ? mainnetManager : testnetManager;
  static String getMarketAddress(String chainId) => chainId == '0xc487' ? mainnetMarket : testnetMarket;

  static const String _managerAbi = '''[
    {"inputs": [{"internalType": "address", "name": "_targetContract", "type": "address"}, {"internalType": "bytes32", "name": "_eventSignature", "type": "bytes32"}, {"internalType": "uint8", "name": "_referrerTopicIndex", "type": "uint8"}, {"internalType": "uint8", "name": "_rewardType", "type": "uint8"}, {"internalType": "uint256", "name": "_rewardValue", "type": "uint256"}, {"internalType": "uint256", "name": "_amountDataOffset", "type": "uint256"}], "name": "createCampaign", "outputs": [], "stateMutability": "payable", "type": "function"},
    {"inputs": [{"internalType": "uint256", "name": "camId", "type": "uint256"}], "name": "fundCampaign", "outputs": [], "stateMutability": "payable", "type": "function"},
    {"inputs": [{"internalType": "uint256", "name": "camId", "type": "uint256"}], "name": "cancelCampaign", "outputs": [], "stateMutability": "nonpayable", "type": "function"},
    {"inputs": [], "name": "nextCampaignId", "outputs": [{"internalType": "uint256", "name": "", "type": "uint256"}], "stateMutability": "view", "type": "function"},
    {"inputs": [{"internalType": "uint256", "name": "", "type": "uint256"}], "name": "campaigns", "outputs": [{"internalType": "address", "name": "marketer", "type": "address"}, {"internalType": "address", "name": "targetContract", "type": "address"}, {"internalType": "bytes32", "name": "eventSignature", "type": "bytes32"}, {"internalType": "uint8", "name": "referrerTopicIndex", "type": "uint8"}, {"internalType": "uint8", "name": "rewardType", "type": "uint8"}, {"internalType": "uint256", "name": "rewardValue", "type": "uint256"}, {"internalType": "uint256", "name": "amountDataOffset", "type": "uint256"}, {"internalType": "uint256", "name": "budgetRemaining", "type": "uint256"}, {"internalType": "bool", "name": "isActive", "type": "bool"}, {"internalType": "uint256", "name": "totalPayouts", "type": "uint256"}, {"internalType": "uint256", "name": "totalConversions", "type": "uint256"}], "stateMutability": "view", "type": "function"},
    {"inputs": [{"internalType": "uint256", "name": "camId", "type": "uint256"}], "name": "getCampaignAffiliates", "outputs": [{"internalType": "address[]", "name": "affiliates", "type": "address[]"}, {"internalType": "uint256[]", "name": "earnings", "type": "uint256[]"}], "stateMutability": "view", "type": "function"}
  ]''';

  static const String _marketAbi = '''[
    {"inputs": [{"internalType": "address", "name": "referrer", "type": "address"}], "name": "buyItem", "outputs": [], "stateMutability": "payable", "type": "function"}
  ]''';

  static web3.DeployedContract getManagerContract(String chainId) => web3.DeployedContract(web3.ContractAbi.fromJson(_managerAbi, 'CampaignManager'), web3.EthereumAddress.fromHex(getManagerAddress(chainId), enforceEip55: false));
  static web3.DeployedContract getMarketContract(String chainId) => web3.DeployedContract(web3.ContractAbi.fromJson(_marketAbi, 'ExampleMarket'), web3.EthereumAddress.fromHex(getMarketAddress(chainId), enforceEip55: false));

  static String encodeCreateCampaign(String chainId, String target, String sigString, int topicIdx, int rewardType, BigInt rewardVal, BigInt offset) {
    debugPrint("[Web3Service] Hashing Signature: $sigString");
    final bytes32Signature = web3_crypto.keccakUtf8(sigString);
    final data = getManagerContract(chainId).function('createCampaign').encodeCall([web3.EthereumAddress.fromHex(target, enforceEip55: false), bytes32Signature, BigInt.from(topicIdx), BigInt.from(rewardType), rewardVal, offset]);
    final payload = "0x${hex.encode(data)}";
    debugPrint("[Web3Service] Encoded Payload: $payload");
    return payload;
  }

  static String encodeCancelCampaign(String chainId, BigInt id) => "0x${hex.encode(getManagerContract(chainId).function('cancelCampaign').encodeCall([id]))}";
  static String encodeFundCampaign(String chainId, BigInt id) => "0x${hex.encode(getManagerContract(chainId).function('fundCampaign').encodeCall([id]))}";
  
  static String encodeBuyItem(String chainId, String referrerAddress) {
    debugPrint("[Web3Service] Encoding buyItem for referrer: $referrerAddress");
    return "0x${hex.encode(getMarketContract(chainId).function('buyItem').encodeCall([web3.EthereumAddress.fromHex(referrerAddress, enforceEip55: false)]))}";
  }

  static String encodeNextCampaignId(String chainId) => "0x${hex.encode(getManagerContract(chainId).function('nextCampaignId').encodeCall([]))}";
  static String encodeGetCampaign(String chainId, BigInt id) => "0x${hex.encode(getManagerContract(chainId).function('campaigns').encodeCall([id]))}";
  static String encodeGetCampaignAffiliates(String chainId, BigInt id) => "0x${hex.encode(getManagerContract(chainId).function('getCampaignAffiliates').encodeCall([id]))}";

  static BigInt decodeUint256(String hexData) {
    final clean = hexData.startsWith('0x') ? hexData.substring(2) : hexData;
    return clean.isEmpty ? BigInt.zero : BigInt.parse(clean, radix: 16);
  }

  static List<dynamic> decodeCampaignData(String chainId, String hexData) => getManagerContract(chainId).function('campaigns').decodeReturnValues(hexData);
  static List<dynamic> decodeCampaignAffiliates(String chainId, String hexData) => getManagerContract(chainId).function('getCampaignAffiliates').decodeReturnValues(hexData);
}

// ==============================================================
// 4. MAIN APPLICATION
// ==============================================================
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ReactRouteApp());
}

class ReactRouteApp extends StatelessWidget {
  const ReactRouteApp({super.key});

  @override
  Widget build(BuildContext context) {
    final params = parseWebUrlParams();
    Widget startScreen = const LandingScreen();
    if (params.containsKey('ref')) startScreen = CheckoutGateway(refAddress: params['ref']);

    return MaterialApp(
      title: 'ReactRoute',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF09090B), 
        textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
        useMaterial3: true,
      ),
      home: startScreen,
    );
  }
}

// ==============================================================
// 5. CORE UI UTILS 
// ==============================================================
class AppColors {
  static const Color bg = Color(0xFF09090B); 
  static const Color card = Color(0xFF18181B); 
  static const Color border = Color(0xFF27272A); 
  static const Color textMain = Color(0xFFFAFAFA); 
  static const Color textSub = Color(0xFFA1A1AA); 
  static const Color primary = Color(0xFF3B82F6); 
  static const Color success = Color(0xFF10B981); 
}

class KeyboardScrollWrapper extends StatefulWidget {
  final Widget child;
  final ScrollController controller;
  const KeyboardScrollWrapper({super.key, required this.child, required this.controller});
  @override State<KeyboardScrollWrapper> createState() => _KeyboardScrollWrapperState();
}

class _KeyboardScrollWrapperState extends State<KeyboardScrollWrapper> {
  final FocusNode _focusNode = FocusNode();
  @override void initState() { super.initState(); WidgetsBinding.instance.addPostFrameCallback((_) { _focusNode.requestFocus(); }); }
  @override void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) { if (FocusManager.instance.primaryFocus?.context?.widget is! EditableText) _focusNode.requestFocus(); },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () { if (FocusManager.instance.primaryFocus?.context?.widget is! EditableText) _focusNode.requestFocus(); },
        child: Focus(
          focusNode: _focusNode, autofocus: true, canRequestFocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent || event is KeyRepeatEvent) {
              if (FocusManager.instance.primaryFocus?.context?.widget is EditableText) return KeyEventResult.ignored;
              const double scrollAmount = 150.0; const double pageScrollAmount = 400.0;
              double target = widget.controller.offset;
              if (event.logicalKey == LogicalKeyboardKey.arrowDown) target += scrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.arrowUp) target -= scrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.pageDown || event.logicalKey == LogicalKeyboardKey.space) target += pageScrollAmount;
              else if (event.logicalKey == LogicalKeyboardKey.pageUp) target -= pageScrollAmount;
              if (target != widget.controller.offset) {
                target = target.clamp(0.0, widget.controller.position.maxScrollExtent);
                widget.controller.animateTo(target, duration: const Duration(milliseconds: 100), curve: Curves.easeOut);
                return KeyEventResult.handled;
              }
            }
            return KeyEventResult.ignored;
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class DeFiCard extends StatelessWidget {
  final Widget child;
  final double? width;
  final EdgeInsetsGeometry padding;
  const DeFiCard({super.key, required this.child, this.width, this.padding = const EdgeInsets.all(32)});

  @override
  Widget build(BuildContext context) {
    return Container(width: width, padding: padding, decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.border, width: 1), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 30, offset: const Offset(0, 10))]), child: child);
  }
}

// ==============================================================
// 6. WEB3 MIXIN (Network, Balance, Explorer, Polling)
// ==============================================================
mixin Web3Utils<T extends StatefulWidget> on State<T> {
  final ScrollController scrollController = ScrollController();
  String _currentChainId = '0xc488';

  @override void dispose() { scrollController.dispose(); super.dispose(); }

  String getExplorerUrl(String chainId, String txHash) {
    if (chainId == '0xc487') return "https://explorer.somnia.network/tx/$txHash";
    return "https://shannon-explorer.somnia.network/tx/$txHash"; 
  }

  Future<bool> waitForReceipt(Ethereum provider, String txHash) async {
    debugPrint("[Receipt] Polling for tx confirmation: $txHash");
    int attempts = 0;
    final jsJson = globalContext.getProperty('JSON'.toJS) as JSObject;
    while (attempts < 30) { 
      await Future.delayed(const Duration(seconds: 2));
      try {
        final resultAny = await provider.request(RequestArguments(method: 'eth_getTransactionReceipt'.toJS, params: [txHash].jsify())).toDart;
        if (resultAny != null) {
          final jsString = jsJson.callMethod('stringify'.toJS, resultAny as JSAny) as JSString?;
          final jsonStr = jsString?.toDart ?? "";
          if (jsonStr.contains('"status":"0x1"')) {
            debugPrint("[Receipt] Transaction MINED successfully.");
            return true;
          } else if (jsonStr.contains('"status":"0x0"')) {
            debugPrint("[Receipt] Transaction REVERTED.");
            return false;
          }
        }
      } catch (e) { debugPrint("[Receipt] Polling error: $e"); }
      attempts++;
    }
    throw Exception("Transaction confirmation timed out.");
  }

  Future<bool> ensureCorrectNetwork(Ethereum provider, BuildContext ctx, Function(String) setStatus) async {
    try {
      debugPrint("[Network] Verifying Chain ID...");
      setStatus("Verifying Network...");
      final currentChainHex = ((await provider.request(RequestArguments(method: 'eth_chainId'.toJS)).toDart) as JSString).toDart.toLowerCase();
      _currentChainId = currentChainHex;
      debugPrint("[Network] Connected to: $currentChainHex");

      if (currentChainHex == '0xc487' || currentChainHex == '0xc488') return true;

      const targetChainId = '0xc487'; 
      setStatus("Please approve network switch in your wallet...");
      try {
        await provider.request(RequestArguments(method: 'wallet_switchEthereumChain'.toJS, params: [{'chainId': targetChainId}].jsify())).toDart;
        _currentChainId = targetChainId; return true;
      } catch (switchError) {
        setStatus("Adding Somnia Mainnet to your wallet...");
        try {
          await provider.request(RequestArguments(method: 'wallet_addEthereumChain'.toJS, params: [{'chainId': targetChainId, 'chainName': 'Somnia Mainnet', 'rpcUrls': ['https://rpc.somnia.network'], 'nativeCurrency': { 'name': 'SOMI', 'symbol': 'SOMI', 'decimals': 18 }, 'blockExplorerUrls': ['https://somnia-explorer.network']}].jsify())).toDart;
          _currentChainId = targetChainId; return true;
        } catch (addError) {
          if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Failed to add network. Please switch to Somnia manually."), backgroundColor: Colors.red));
          return false;
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text("Wallet communication error."), backgroundColor: Colors.red));
      return false;
    }
  }

  Future<BigInt> getBalance(Ethereum provider, String address) async {
    debugPrint("[Balance] Fetching for $address...");
    try {
      final res = await provider.request(RequestArguments(method: 'eth_getBalance'.toJS, params: [address, 'latest'].jsify())).toDart;
      final bal = Web3Service.decodeUint256((res as JSString).toDart);
      debugPrint("[Balance] Wei: $bal");
      return bal;
    } catch (e) { return BigInt.zero; }
  }

  void showWalletSelector(BuildContext context, Function(String, Ethereum, String) onConnected) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        bool isConnecting = false;
        return StatefulBuilder(
          builder: (context, setState) {
            return Center(
              child: Material(
                color: Colors.transparent,
                child: DeFiCard(
                  width: 400, padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Connect Wallet", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textMain)), IconButton(icon: const Icon(Icons.close, color: AppColors.textSub, size: 20), onPressed: () => Navigator.pop(context), splashRadius: 20)]),
                      const SizedBox(height: 16),
                      if (isConnecting) const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
                      else ...[
                        _buildWalletOpt("MetaMask", "Injected", Icons.pets, Colors.orange, () async { setState(() => isConnecting = true); await _connectProvider(ethereum, context, onConnected, () => setState(() => isConnecting = false)); }),
                        _buildWalletOpt("Coinbase Wallet", "Extension", Icons.account_balance_wallet, Colors.blue, () async { setState(() => isConnecting = true); final provider = coinbaseWalletExtension ?? ((ethereum?.isCoinbaseWallet == true) ? ethereum : null); await _connectProvider(provider, context, onConnected, () => setState(() => isConnecting = false)); }),
                        _buildWalletOpt("Trust Wallet", "Injected", Icons.shield, Colors.lightBlue, () async { setState(() => isConnecting = true); final provider = trustWallet ?? ((ethereum?.isTrust == true) ? ethereum : null); await _connectProvider(provider, context, onConnected, () => setState(() => isConnecting = false)); }),
                        _buildWalletOpt("Phantom", "EVM Ready", Icons.visibility, Colors.deepPurple, () async { setState(() => isConnecting = true); final provider = phantomWallet ?? ((ethereum?.isPhantom == true) ? ethereum : null); await _connectProvider(provider, context, onConnected, () => setState(() => isConnecting = false)); }),
                        _buildWalletOpt("Rabby Wallet", "Extension", Icons.security, Colors.indigoAccent, () async { setState(() => isConnecting = true); final provider = (ethereum != null && ethereum!.isRabby == true) ? ethereum : null; await _connectProvider(provider, context, onConnected, () => setState(() => isConnecting = false)); }),
                      ]
                    ],
                  ),
                ),
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _connectProvider(Ethereum? provider, BuildContext context, Function(String, Ethereum, String) onSuccess, VoidCallback onFail) async {
    debugPrint("[Wallet] Attempting connection...");
    if (provider == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wallet not detected. Please install the extension."), backgroundColor: Colors.red)); onFail(); return; }
    try {
      try { await provider.request(RequestArguments(method: 'wallet_requestPermissions'.toJS, params: [{'eth_accounts': {}}].jsify())).toDart; } catch (e) { debugPrint("Permissions skipped"); }
      final args = RequestArguments(method: 'eth_requestAccounts'.toJS);
      final result = await provider.request(args).toDart as JSArray;
      if (result.length > 0) {
        final addr = (result[0] as JSString).toDart;
        final currentChainHex = ((await provider.request(RequestArguments(method: 'eth_chainId'.toJS)).toDart) as JSString).toDart.toLowerCase();
        debugPrint("[Wallet] Connected successfully: $addr");
        Navigator.pop(context); 
        onSuccess(addr, provider, currentChainHex);
      }
    } catch (e) { debugPrint("[Wallet] Connection failed: $e"); onFail(); }
  }

  Widget _buildWalletOpt(String name, String sub, IconData icon, Color color, VoidCallback onTap) {
    return Padding(padding: const EdgeInsets.only(bottom: 8.0), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16), decoration: BoxDecoration(color: AppColors.bg, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: Row(children: [Icon(icon, color: color, size: 24), const SizedBox(width: 16), Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textMain)), const Spacer(), Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.textSub))]))));
  }
}

// ==============================================================
// 7. LANDING SCREEN
// ==============================================================
class LandingScreen extends StatefulWidget { const LandingScreen({super.key}); @override State<LandingScreen> createState() => _LandingScreenState(); }
class _LandingScreenState extends State<LandingScreen> with Web3Utils {
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(preferredSize: const Size.fromHeight(70), child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), padding: const EdgeInsets.symmetric(horizontal: 40), alignment: Alignment.centerLeft, child: Row(children: const [Icon(Icons.route_rounded, color: AppColors.primary, size: 28), SizedBox(width: 12), Text("ReactRoute", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textMain, letterSpacing: -0.5))]))),
      body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: SingleChildScrollView(controller: scrollController, child: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(vertical: 120, horizontal: 24), child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 900), child: Column(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.primary.withOpacity(0.3))), child: const Text("Built for Somnia Reactivity", style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600))),
          const SizedBox(height: 24), const Text("Decentralized Affiliate Routing.", style: TextStyle(fontSize: 64, fontWeight: FontWeight.w800, color: AppColors.textMain, letterSpacing: -2, height: 1.1), textAlign: TextAlign.center).animate().fadeIn(duration: 600.ms).slideY(begin: 0.1),
          const SizedBox(height: 24), const Text("Plug any existing smart contract into our reactivity engine. Launch a zero-touch affiliate program instantly, without modifying your core codebase.", style: TextStyle(fontSize: 20, color: AppColors.textSub, height: 1.5), textAlign: TextAlign.center).animate().fadeIn(delay: 200.ms),
          const SizedBox(height: 60),
          Wrap(spacing: 24, runSpacing: 24, alignment: WrapAlignment.center, children: [
            _buildPortalCard("Marketer", "Deploy Campaigns", Icons.campaign, () => Navigator.pushReplacement(context, MaterialPageRoute(settings: const RouteSettings(name: '/marketer'), builder: (_) => const MarketerGateway()))),
            _buildPortalCard("Affiliate", "Track Earnings", Icons.people, () => Navigator.pushReplacement(context, MaterialPageRoute(settings: const RouteSettings(name: '/affiliate'), builder: (_) => const AffiliateGateway()))),
            _buildPortalCard("Sandbox", "Test Network", Icons.code, () => Navigator.pushReplacement(context, MaterialPageRoute(settings: const RouteSettings(name: '/checkout'), builder: (_) => const CheckoutGateway()))),
          ]).animate().fadeIn(delay: 400.ms)
        ])))),
        Container(height: 1, color: AppColors.border),
        Padding(padding: const EdgeInsets.symmetric(vertical: 80, horizontal: 24), child: Container(constraints: const BoxConstraints(maxWidth: 1000), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _buildFeature(Icons.lock_outline, "No Redeployment", "Traditional programs require altering your contract. ReactRoute listens to events dynamically off-chain and executes payouts securely.")),
          const SizedBox(width: 40),
          Expanded(child: _buildFeature(Icons.bolt, "Atomic Execution", "The millisecond a conversion event fires on Somnia, our Sentinel extracts the referrer and routes the capital in the same block.")),
        ])))
      ])))),
    );
  }

  Widget _buildPortalCard(String title, String sub, IconData icon, VoidCallback onTap) {
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(12), child: Container(width: 260, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppColors.textMain, size: 28), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textMain)), const SizedBox(height: 4), Text(sub, style: const TextStyle(fontSize: 14, color: AppColors.textSub))])));
  }

  Widget _buildFeature(IconData icon, String title, String desc) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: AppColors.primary, size: 32), const SizedBox(height: 16), Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textMain)), const SizedBox(height: 8), Text(desc, style: const TextStyle(fontSize: 16, color: AppColors.textSub, height: 1.6))]);
  }
}

// ==============================================================
// 8. GATEWAYS 
// ==============================================================
class MarketerGateway extends StatefulWidget { const MarketerGateway({super.key}); @override State<MarketerGateway> createState() => _MarketerGatewayState(); }
class _MarketerGatewayState extends State<MarketerGateway> with Web3Utils {
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(backgroundColor: AppColors.bg, elevation: 0, leading: const BackButton(color: AppColors.textMain)), body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 600), padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Deploy. Fund. Scale.", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.textMain, letterSpacing: -1.5, height: 1.1)), const SizedBox(height: 24), const Text("Register your existing Somnia contract into the ReactRoute engine. Set conversion events, define your revenue split, and fund your marketing vault securely.", style: TextStyle(fontSize: 18, color: AppColors.textSub, height: 1.6)), const SizedBox(height: 40), ElevatedButton(onPressed: () => showWalletSelector(context, (addr, prov, chain) => Navigator.pushReplacement(context, MaterialPageRoute(settings: const RouteSettings(name: '/marketer'), builder: (_) => MarketerDashboard(address: addr, provider: prov, initChainId: chain)))), style: ElevatedButton.styleFrom(backgroundColor: AppColors.textMain, foregroundColor: AppColors.bg, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text("Connect Wallet to Deploy", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))]))))));
  }
}

class AffiliateGateway extends StatefulWidget { const AffiliateGateway({super.key}); @override State<AffiliateGateway> createState() => _AffiliateGatewayState(); }
class _AffiliateGatewayState extends State<AffiliateGateway> with Web3Utils {
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(backgroundColor: AppColors.bg, elevation: 0, leading: const BackButton(color: AppColors.textMain)), body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 600), padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Monetize Your Influence.", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.textMain, letterSpacing: -1.5, height: 1.1)), const SizedBox(height: 24), const Text("Browse active on-chain campaigns, generate immutable referral links, and watch your earnings route instantly to your wallet via Somnia Reactivity. Zero manual claiming.", style: TextStyle(fontSize: 18, color: AppColors.textSub, height: 1.6)), const SizedBox(height: 40), ElevatedButton(onPressed: () => showWalletSelector(context, (addr, prov, chain) => Navigator.pushReplacement(context, MaterialPageRoute(settings: const RouteSettings(name: '/affiliate'), builder: (_) => AffiliateDashboard(address: addr, provider: prov, initChainId: chain)))), style: ElevatedButton.styleFrom(backgroundColor: AppColors.textMain, foregroundColor: AppColors.bg, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text("Connect Wallet to Earn", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))]))))));
  }
}

class CheckoutGateway extends StatefulWidget { final String? refAddress; const CheckoutGateway({super.key, this.refAddress}); @override State<CheckoutGateway> createState() => _CheckoutGatewayState(); }
class _CheckoutGatewayState extends State<CheckoutGateway> with Web3Utils {
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(backgroundColor: AppColors.bg, elevation: 0, leading: const BackButton(color: AppColors.textMain)), body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 600), padding: const EdgeInsets.all(24), child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Live Network Sandbox.", style: TextStyle(fontSize: 48, fontWeight: FontWeight.w800, color: AppColors.textMain, letterSpacing: -1.5, height: 1.1)), const SizedBox(height: 24), const Text("A simulated Web3 storefront to test the protocol end-to-end. Purchasing here triggers the ReactRoute Sentinel to verify event interception and payout routing.", style: TextStyle(fontSize: 18, color: AppColors.textSub, height: 1.6)), const SizedBox(height: 40), ElevatedButton(onPressed: () => showWalletSelector(context, (addr, prov, chain) => Navigator.pushReplacement(context, MaterialPageRoute(settings: RouteSettings(name: widget.refAddress != null ? '/checkout?ref=${widget.refAddress}' : '/checkout'), builder: (_) => CheckoutScreen(address: addr, provider: prov, initChainId: chain, refAddress: widget.refAddress)))), style: ElevatedButton.styleFrom(backgroundColor: AppColors.textMain, foregroundColor: AppColors.bg, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), child: const Text("Connect Buyer Wallet", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)))]))))));
  }
}

// ==============================================================
// 9. MARKETER DASHBOARD
// ==============================================================
class MarketerDashboard extends StatefulWidget {
  final String address;
  final Ethereum provider;
  final String initChainId;
  const MarketerDashboard({super.key, required this.address, required this.provider, required this.initChainId});
  @override
  State<MarketerDashboard> createState() => _MarketerDashboardState();
}

class _MarketerDashboardState extends State<MarketerDashboard> with Web3Utils, SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  late TextEditingController _targetCtrl;
  final _sigCtrl = TextEditingController(text: "ItemBought(address,address,uint256)");
  final _topicCtrl = TextEditingController(text: "2");
  final _valCtrl = TextEditingController(text: "10"); 
  final _offsetCtrl = TextEditingController(text: "0");
  final _budgetCtrl = TextEditingController();
  String _type = "Percentage (Industry Standard)";
  bool _isTransacting = false;
  String _statusMessage = "";
  String? _txHash;
  bool _isFailedTx = false;

  bool _isLoadingManage = true;
  List<CampaignData> _myCampaigns = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() { if (_tabController.index == 1) _fetchMyCampaigns(); });
    _targetCtrl = TextEditingController(text: Web3Service.getMarketAddress(widget.initChainId));
    _currentChainId = widget.initChainId;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchMyCampaigns() async {
    debugPrint("\n--- FETCHING MY CAMPAIGNS ---");
    setState(() => _isLoadingManage = true);
    if (!await ensureCorrectNetwork(widget.provider, context, (s) {})) return;
    try {
      final totalHex = ((await widget.provider.request(RequestArguments(method: 'eth_call'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'data': Web3Service.encodeNextCampaignId(_currentChainId)}.jsify(), 'latest'.toJS].jsify())).toDart) as JSString).toDart;
      int total = Web3Service.decodeUint256(totalHex).toInt();
      debugPrint("[Manage] Total Campaigns deployed globally: $total");
      
      List<CampaignData> list = [];
      for (int i = total - 1; i >= 1; i--) {
        try {
          final res = ((await widget.provider.request(RequestArguments(method: 'eth_call'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'data': Web3Service.encodeGetCampaign(_currentChainId, BigInt.from(i))}.jsify(), 'latest'.toJS].jsify())).toDart) as JSString).toDart;
          if (res.length > 10 && res != '0x') {
            final d = Web3Service.decodeCampaignData(_currentChainId, res);
            final marketer = (d[0] as web3.EthereumAddress).hex.toLowerCase();
            
            if (marketer == widget.address.toLowerCase()) {
              debugPrint("[Manage] Found matching campaign ID: $i");
              
              List<AffiliateStat> affStats = [];
              try {
                final affRes = ((await widget.provider.request(RequestArguments(method: 'eth_call'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'data': Web3Service.encodeGetCampaignAffiliates(_currentChainId, BigInt.from(i))}.jsify(), 'latest'.toJS].jsify())).toDart) as JSString).toDart;
                if (affRes.length > 10 && affRes != '0x') {
                  final affDecoded = Web3Service.decodeCampaignAffiliates(_currentChainId, affRes);
                  final addresses = affDecoded[0] as List;
                  final earnings = affDecoded[1] as List;
                  for(int j = 0; j < addresses.length; j++) {
                    affStats.add(AffiliateStat((addresses[j] as web3.EthereumAddress).hex, earnings[j] as BigInt));
                  }
                  debugPrint("[Manage] Loaded ${affStats.length} affiliates for Campaign $i");
                }
              } catch (e) { debugPrint("[Manage] Affiliate Fetch Error: $e"); }

              list.add(CampaignData(
                id: i, marketer: marketer, targetContract: (d[1] as web3.EthereumAddress).hex, 
                rewardType: (d[4] as BigInt).toInt(), rewardValue: d[5] as BigInt, 
                budgetRemaining: d[7] as BigInt, isActive: d[8] as bool,
                totalPayouts: d[9] as BigInt, totalConversions: d[10] as BigInt,
                affiliates: affStats
              ));
            }
          }
        } catch (e) { debugPrint("[Manage] Error decoding campaign $i: $e"); }
      }
      if (mounted) setState(() => _myCampaigns = list);
    } catch (e) { debugPrint("[Manage] Fetch err: $e"); } 
    finally { if (mounted) setState(() => _isLoadingManage = false); }
  }

  Future<void> _fundCampaign(int id) async {
    String amt = "";
    bool proceed = await showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppColors.card, title: const Text("Fund Campaign"), content: TextField(onChanged: (v) => amt = v, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: "Amount in SOMI", filled: true, fillColor: AppColors.bg), style: const TextStyle(color: Colors.white)), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text("Fund"))])) ?? false;
    if (!proceed || amt.isEmpty) return;
    
    double val = double.tryParse(amt) ?? 0.0;
    if (val <= 0) return;
    BigInt weiVal = BigInt.from(val * 1000000) * BigInt.from(10).pow(12);

    try {
      debugPrint("[Fund] Initiating funding for Campaign $id. Amount: $weiVal Wei");
      final payload = Web3Service.encodeFundCampaign(_currentChainId, BigInt.from(id));
      final txHash = ((await widget.provider.request(RequestArguments(method: 'eth_sendTransaction'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'from': widget.address, 'data': payload, 'value': "0x${weiVal.toRadixString(16)}", 'gas': '0x2dc6c0'}].jsify())).toDart) as JSString).toDart;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Funding tx sent: $txHash"), backgroundColor: AppColors.success));
      await waitForReceipt(widget.provider, txHash);
      _fetchMyCampaigns();
    } catch (e) { debugPrint("[Fund] Error: $e"); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Funding failed: $e"), backgroundColor: Colors.red)); }
  }

  Future<void> _cancelCampaign(int id) async {
    bool proceed = await showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: AppColors.card, title: const Text("Cancel Campaign?"), content: const Text("This will deactivate the campaign and refund the remaining budget to your wallet. Are you sure?"), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("No", style: TextStyle(color: AppColors.textMain))), ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text("Yes, Cancel", style: TextStyle(color: Colors.white)))])) ?? false;
    if (!proceed) return;

    try {
      debugPrint("[Cancel] Initiating cancellation for Campaign $id");
      final payload = Web3Service.encodeCancelCampaign(_currentChainId, BigInt.from(id));
      final txHash = ((await widget.provider.request(RequestArguments(method: 'eth_sendTransaction'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'from': widget.address, 'data': payload, 'gas': '0x2dc6c0'}].jsify())).toDart) as JSString).toDart;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancellation tx sent: $txHash"), backgroundColor: Colors.orange));
      await waitForReceipt(widget.provider, txHash);
      _fetchMyCampaigns();
    } catch (e) { debugPrint("[Cancel] Error: $e"); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Cancel failed: $e"), backgroundColor: Colors.red)); }
  }

  Future<void> _deploy() async {
    debugPrint("\n--- DEPLOYMENT STARTED ---");
    if (_targetCtrl.text.trim().isEmpty || _valCtrl.text.trim().isEmpty || _budgetCtrl.text.trim().isEmpty) {
      debugPrint("[Deploy] Error: Missing fields.");
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please complete all required fields."))); return;
    }
    setState(() { _isTransacting = true; _txHash = null; _isFailedTx = false; });

    if (!await ensureCorrectNetwork(widget.provider, context, (s) => setState(() => _statusMessage = s))) {
      setState(() => _isTransacting = false); return;
    }

    final bDouble = double.tryParse(_budgetCtrl.text) ?? 0.0;
    if (bDouble <= 0) { setState(() { _isTransacting = false; _statusMessage = "Invalid budget amount."; }); return; }
    final bWei = BigInt.from(bDouble * 1000000) * BigInt.from(10).pow(12);

    final bal = await getBalance(widget.provider, widget.address);
    if (bal < bWei) { setState(() { _isTransacting = false; _statusMessage = "Insufficient balance in wallet."; }); return; }

    try {
      setState(() => _statusMessage = "Awaiting wallet confirmation...");
      final isPct = _type.contains("Percentage");
      
      double rawVal = double.tryParse(_valCtrl.text) ?? 0.0;
      BigInt pVal = isPct ? BigInt.from(rawVal * 100) : BigInt.from(rawVal * 1000000) * BigInt.from(10).pow(12);
      int topicIdx = int.tryParse(_topicCtrl.text) ?? 2;
      BigInt offset = BigInt.tryParse(_offsetCtrl.text) ?? BigInt.zero;
      
      debugPrint("[Deploy] Target: ${_targetCtrl.text}, Value: $pVal, TopicIdx: $topicIdx");
      final payload = Web3Service.encodeCreateCampaign(_currentChainId, _targetCtrl.text.trim(), _sigCtrl.text.trim(), topicIdx, isPct ? 1 : 0, pVal, offset);
      final hexValue = "0x${bWei.toRadixString(16)}";

      debugPrint("[Deploy] Sending Transaction...");
      final txHash = ((await widget.provider.request(RequestArguments(method: 'eth_sendTransaction'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'from': widget.address, 'data': payload, 'value': hexValue, 'gas': '0x2dc6c0'}].jsify())).toDart) as JSString).toDart;
      
      setState(() => _statusMessage = "Confirming on-chain...");
      final success = await waitForReceipt(widget.provider, txHash);
      if (!success) {
        setState(() { _isFailedTx = true; _txHash = txHash; });
        return;
      }
      setState(() { _isFailedTx = false; _txHash = txHash; });
    } catch (e) {
      debugPrint("[Deploy] Error: $e");
      String errMsg = "Transaction failed.";
      if (e.toString().contains("insufficient funds")) errMsg = "Transaction failed: Insufficient gas/funds.";
      else if (e.toString().contains("rejected")) errMsg = "Transaction rejected by user.";
      else errMsg = e.toString();
      setState(() => _statusMessage = errMsg);
    } finally {
      debugPrint("--- DEPLOYMENT ENDED ---\n");
      setState(() => _isTransacting = false);
    }
  }

  void _reset() {
    setState(() { _txHash = null; _isTransacting = false; _statusMessage = ""; _isFailedTx = false; });
    _budgetCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    String networkLabel = _currentChainId == '0xc487' ? "Mainnet" : "Testnet";
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(120),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Marketer Console", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                  Row(
                    children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: _currentChainId == '0xc487' ? AppColors.primary.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Text(networkLabel, style: TextStyle(color: _currentChainId == '0xc487' ? AppColors.primary : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)), child: Text("${widget.address.substring(0,6)}...${widget.address.substring(38)}", style: const TextStyle(fontSize: 14, color: AppColors.textSub, fontFamily: 'monospace'))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.primary, labelColor: AppColors.primary, unselectedLabelColor: AppColors.textSub,
                tabs: const [Tab(text: "Launch Campaign"), Tab(text: "Manage Campaigns")],
              ),
            ],
          ),
        ),
      ),
      body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(), 
        children: [
          _buildLaunchTab(),
          _buildManageTab(),
        ],
      ))),
    );
  }

  Widget _buildLaunchTab() {
    return SingleChildScrollView(controller: scrollController, padding: const EdgeInsets.all(40), child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DeFiCard(
                padding: const EdgeInsets.all(40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Contract Details", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                    const SizedBox(height: 24),
                    _buildLabelWithInfo("Target Contract Address", "The deployed address of the contract you want to track events on."),
                    _buildPremiumInput("e.g. 0x123...", _targetCtrl, Icons.link),
                    const SizedBox(height: 20),
                    _buildLabelWithInfo("Event Signature", "The exact string format of the event your contract emits on a conversion. E.g. ItemBought(address,address,uint256)"),
                    _buildPremiumInput("Event(type,type)", _sigCtrl, Icons.code),
                    const SizedBox(height: 40),
                    
                    const Text("Routing Logic", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                    const SizedBox(height: 24),
                    _buildLabelWithInfo("Reward Type", "Percentage pays a cut of the sale volume. Flat Bounty pays a fixed SOMI amount per event."),
                    DropdownButtonFormField<String>(
                      value: _type, dropdownColor: AppColors.card,
                      decoration: InputDecoration(prefixIcon: const Icon(Icons.calculate, color: AppColors.primary), filled: true, fillColor: AppColors.bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border))),
                      items: ["Percentage (Industry Standard)", "Flat Bounty (Fixed SOMI)"].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: AppColors.textMain)))).toList(),
                      onChanged: (v) => setState(() => _type = v!),
                    ),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildLabelWithInfo(_type.contains("Percentage") ? "Reward Rate (%)" : "Bounty (SOMI)", "The amount the referrer receives."),
                        _buildPremiumInput("Amount", _valCtrl, Icons.percent, isNum: true)
                      ])),
                      const SizedBox(width: 16),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _buildLabelWithInfo("Referrer Topic Index", "Where the affiliate's address lives in your event log (usually index 1, 2, or 3 depending on which parameters are marked 'indexed')."),
                        _buildPremiumInput("Index (e.g. 2)", _topicCtrl, Icons.person_search, isNum: true)
                      ])),
                    ]),
                    if (_type.contains("Percentage")) ...[
                      const SizedBox(height: 20), 
                      _buildLabelWithInfo("Amount Data Offset (Bytes)", "Where the purchase amount lives in your event's unindexed data payload. (Usually 0 if it is the first unindexed parameter)."),
                      _buildPremiumInput("Offset (e.g. 0 or 32)", _offsetCtrl, Icons.data_object, isNum: true),
                    ],
                    const SizedBox(height: 40),
                    
                    const Text("Treasury Funding", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                    const SizedBox(height: 24),
                    _buildLabelWithInfo("Initial Treasury Budget (SOMI)", "The amount of SOMI to lock into the treasury vault to pay your affiliates."),
                    _buildPremiumInput("Amount in SOMI", _budgetCtrl, Icons.account_balance_wallet, isNum: true),
                    const SizedBox(height: 48),

                    if (_txHash != null) ...[
                      Container(
                        width: double.infinity, padding: const EdgeInsets.all(24), 
                        decoration: BoxDecoration(
                          color: _isFailedTx ? Colors.redAccent.withOpacity(0.1) : AppColors.success.withOpacity(0.1), 
                          borderRadius: BorderRadius.circular(16), 
                          border: Border.all(color: _isFailedTx ? Colors.redAccent.withOpacity(0.3) : AppColors.success.withOpacity(0.3))
                        ),
                        child: Column(children: [
                          Icon(_isFailedTx ? Icons.error_outline : Icons.check_circle, color: _isFailedTx ? Colors.redAccent : AppColors.success, size: 40), const SizedBox(height: 12),
                          Text(_isFailedTx ? "Transaction Reverted by Smart Contract" : "Campaign Registered Successfully!", style: TextStyle(color: _isFailedTx ? Colors.redAccent : AppColors.success, fontWeight: FontWeight.bold, fontSize: 20)), const SizedBox(height: 12),
                          InkWell(
                            onTap: () => web.window.open(getExplorerUrl(_currentChainId, _txHash!), '_blank'),
                            child: MouseRegion(cursor: SystemMouseCursors.click, child: Text("View exactly why on Explorer ↗\n${getExplorerUrl(_currentChainId, _txHash!)}", style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline, fontSize: 13, fontFamily: 'monospace', height: 1.5), textAlign: TextAlign.center)),
                          ),
                        ]),
                      ).animate().fadeIn(),
                      const SizedBox(height: 24),
                      SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _reset, icon: const Icon(Icons.refresh, color: AppColors.textMain), label: const Text("Deploy Another Campaign", style: TextStyle(color: AppColors.textMain)), style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 20), side: const BorderSide(color: AppColors.border), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))))
                    ] else ...[
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isTransacting ? null : _deploy,
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.textMain, foregroundColor: AppColors.bg, padding: const EdgeInsets.symmetric(vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                          child: _isTransacting ? Text(_statusMessage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)) : const Text("Deploy & Fund Campaign", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ]
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms).slideX(begin: 0.1, end: 0)
            ],
          ),
        ),
      ));
  }

  Widget _buildManageTab() {
    if (_isLoadingManage) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    if (_myCampaigns.isEmpty) return const Center(child: Text("You have not deployed any campaigns yet.", style: TextStyle(color: AppColors.textSub, fontSize: 16)));
    
    return SingleChildScrollView(padding: const EdgeInsets.all(40), child: Center(child: Container(constraints: const BoxConstraints(maxWidth: 900), child: Column(
      children: _myCampaigns.map((c) {
        String rTxt = c.rewardType == 1 ? "${c.rewardValue.toInt() / 100}%" : "${c.rewardValue / BigInt.from(10).pow(18)} SOMI";
        return Padding(padding: const EdgeInsets.only(bottom: 24), child: DeFiCard(padding: const EdgeInsets.all(32), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Campaign #${c.id}", style: const TextStyle(color: AppColors.textSub, fontSize: 12)),
              const SizedBox(height: 4),
              Text(c.targetContract, style: TextStyle(color: c.isActive ? AppColors.textMain : AppColors.textSub, fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: c.isActive ? AppColors.success.withOpacity(0.1) : Colors.redAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(c.isActive ? "ACTIVE" : "CANCELLED", style: TextStyle(color: c.isActive ? AppColors.success : Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)))
          ]),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: _buildStatBox("Remaining Budget", "${(c.budgetRemaining / BigInt.from(10).pow(18)).toStringAsFixed(4)} SOMI")),
            const SizedBox(width: 16),
            Expanded(child: _buildStatBox("Total Payouts", "${(c.totalPayouts / BigInt.from(10).pow(18)).toStringAsFixed(4)} SOMI")),
            const SizedBox(width: 16),
            Expanded(child: _buildStatBox("Conversions", c.totalConversions.toString())),
          ]),
          const SizedBox(height: 24),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(6), border: Border.all(color: AppColors.border)), child: Text("Reward: $rTxt", style: const TextStyle(color: AppColors.textSub, fontSize: 12))),
            const Spacer(),
            if (c.isActive) ...[
              OutlinedButton.icon(onPressed: () => _fundCampaign(c.id), icon: const Icon(Icons.add, size: 16, color: AppColors.primary), label: const Text("Top-Up Vault", style: TextStyle(color: AppColors.primary)), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border))),
              const SizedBox(width: 12),
              OutlinedButton.icon(onPressed: () => _cancelCampaign(c.id), icon: const Icon(Icons.close, size: 16, color: Colors.redAccent), label: const Text("Cancel", style: TextStyle(color: Colors.redAccent)), style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.border))),
            ]
          ]),
          
          // AFFILIATE LEADERBOARD
          if (c.isActive || c.affiliates.isNotEmpty) ...[
            const SizedBox(height: 24),
            Container(
              decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(20), 
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Affiliate Leaderboard", style: TextStyle(color: AppColors.textMain, fontSize: 16, fontWeight: FontWeight.bold)),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(20)), child: Text("${c.affiliates.length} Active Promoters", style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)))
                      ]
                    )
                  ),
                  Container(height: 1, color: AppColors.border),
                  if (c.affiliates.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Center(child: Text("No affiliates have driven conversions yet.", style: TextStyle(color: AppColors.textSub)))),
                  ...c.affiliates.map((a) => Container(
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle, border: Border.all(color: AppColors.border)), child: const Icon(Icons.person, color: AppColors.primary, size: 20)),
                      title: Text(a.address, style: const TextStyle(color: AppColors.textMain, fontFamily: 'monospace', fontSize: 14)),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Text("Total Earned", style: TextStyle(color: AppColors.textSub, fontSize: 10)),
                          const SizedBox(height: 4),
                          Text("${(a.earnings / BigInt.parse("1000000000000000000")).toStringAsFixed(4)} SOMI", style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                  )).toList()
                ]
              )
            )
          ]
        ])));
      }).toList(),
    ))));
  }

  Widget _buildStatBox(String label, String val) {
    return Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label, style: const TextStyle(color: AppColors.textSub, fontSize: 12)), const SizedBox(height: 8), Text(val, style: const TextStyle(color: AppColors.textMain, fontSize: 18, fontWeight: FontWeight.bold))]));
  }

  Widget _buildLabelWithInfo(String text, String tooltipMessage) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(mainAxisSize: MainAxisSize.min, children: [Text(text, style: const TextStyle(color: AppColors.textMain, fontSize: 14, fontWeight: FontWeight.w500)), const SizedBox(width: 8), Tooltip(message: tooltipMessage, padding: const EdgeInsets.all(12), margin: const EdgeInsets.symmetric(horizontal: 24), textStyle: const TextStyle(color: Colors.white, fontSize: 13), decoration: BoxDecoration(color: AppColors.card, border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.info_outline, size: 16, color: AppColors.textSub))]));
  }

  Widget _buildPremiumInput(String placeholder, TextEditingController ctrl, IconData icon, {bool isNum = false}) {
    return TextField(controller: ctrl, keyboardType: isNum ? TextInputType.number : TextInputType.text, style: const TextStyle(color: AppColors.textMain, fontSize: 15), decoration: InputDecoration(hintText: placeholder, hintStyle: TextStyle(color: AppColors.textSub.withOpacity(0.5)), prefixIcon: Icon(icon, color: AppColors.primary), filled: true, fillColor: AppColors.bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)), enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary))));
  }
}

// ==============================================================
// 10. AFFILIATE DASHBOARD (B2C UI)
// ==============================================================
class AffiliateDashboard extends StatefulWidget {
  final String address;
  final Ethereum provider;
  final String initChainId;
  const AffiliateDashboard({super.key, required this.address, required this.provider, required this.initChainId});
  @override
  State<AffiliateDashboard> createState() => _AffiliateDashboardState();
}

class _AffiliateDashboardState extends State<AffiliateDashboard> with Web3Utils {
  bool _isLoading = true;
  List<CampaignData> _campaigns = [];
  BigInt _bal = BigInt.zero;

  @override
  void initState() {
    super.initState();
    _currentChainId = widget.initChainId;
    _fetch();
  }

  Future<void> _fetch() async {
    debugPrint("\n--- FETCHING CAMPAIGNS ---");
    if (!await ensureCorrectNetwork(widget.provider, context, (s) {})) return;
    try {
      _bal = await getBalance(widget.provider, widget.address);
      final totalHex = ((await widget.provider.request(RequestArguments(method: 'eth_call'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'data': Web3Service.encodeNextCampaignId(_currentChainId)}.jsify(), 'latest'.toJS].jsify())).toDart) as JSString).toDart;
      int total = Web3Service.decodeUint256(totalHex).toInt();
      debugPrint("[Affiliate] Total campaigns discovered: $total");
      
      List<CampaignData> list = [];
      for (int i = total - 1; i >= 1; i--) {
        try {
          final res = ((await widget.provider.request(RequestArguments(method: 'eth_call'.toJS, params: [{'to': Web3Service.getManagerAddress(_currentChainId), 'data': Web3Service.encodeGetCampaign(_currentChainId, BigInt.from(i))}.jsify(), 'latest'.toJS].jsify())).toDart) as JSString).toDart;
          if (res.length > 10 && res != '0x') {
            final d = Web3Service.decodeCampaignData(_currentChainId, res);
            if (d[8] == true) list.add(CampaignData(id: i, marketer: (d[0] as web3.EthereumAddress).hex, targetContract: (d[1] as web3.EthereumAddress).hex, rewardType: (d[4] as BigInt).toInt(), rewardValue: d[5] as BigInt, budgetRemaining: d[7] as BigInt, isActive: true, totalPayouts: d[9] as BigInt, totalConversions: d[10] as BigInt, affiliates: []));
          }
        } catch (e) { debugPrint("[Affiliate] Error decoding campaign $i: $e"); }
      }
      debugPrint("[Affiliate] Rendered ${list.length} active campaigns.");
      if (mounted) setState(() => _campaigns = list);
    } catch (e) { 
      debugPrint("[Affiliate] CRITICAL Error fetching campaigns: $e"); 
    } finally { 
      debugPrint("--- FETCHING ENDED ---\n");
      if (mounted) setState(() => _isLoading = false); 
    }
  }

  void _copy(String contract) {
    String link = "${web.window.location.href.split('#')[0]}#/checkout?ref=${widget.address}";
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Link copied to clipboard."), backgroundColor: AppColors.primary));
  }

  @override
  Widget build(BuildContext context) {
    double balUi = _bal / BigInt.from(10).pow(18);
    String networkLabel = _currentChainId == '0xc487' ? "Mainnet" : "Testnet";
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Container(
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Affiliate Console", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textMain)),
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: _currentChainId == '0xc487' ? AppColors.primary.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Text(networkLabel, style: TextStyle(color: _currentChainId == '0xc487' ? AppColors.primary : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))),
                const SizedBox(width: 16),
                Text("${balUi.toStringAsFixed(4)} SOMI", style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(width: 16),
                Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)), child: Text("${widget.address.substring(0,6)}...${widget.address.substring(38)}", style: const TextStyle(fontSize: 14, color: AppColors.textSub, fontFamily: 'monospace'))),
              ])
            ],
          ),
        ),
      ),
      body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: _isLoading ? const Center(child: CircularProgressIndicator(color: AppColors.textMain)) : SingleChildScrollView(controller: scrollController, padding: const EdgeInsets.all(40), child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                const Text("Active Campaigns", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textMain)),
                IconButton(icon: const Icon(Icons.refresh, color: AppColors.textSub), onPressed: () { setState(()=>_isLoading=true); _fetch(); })
              ]),
              const SizedBox(height: 24),
              ..._campaigns.map((c) => _buildCard(c)),
              if (_campaigns.isEmpty) const Text("No campaigns found.", style: TextStyle(color: AppColors.textSub))
            ],
          ),
        ),
      )))),
    );
  }

  Widget _buildCard(CampaignData c) {
    String rTxt = c.rewardType == 1 ? "${c.rewardValue.toInt() / 100}%" : "${c.rewardValue / BigInt.from(10).pow(18)} SOMI";
    return Padding(padding: const EdgeInsets.only(bottom: 16), child: DeFiCard(
      padding: const EdgeInsets.all(32),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("Target", style: TextStyle(color: AppColors.textSub, fontSize: 13)),
          const SizedBox(height: 4), Text(c.targetContract, style: const TextStyle(color: AppColors.textMain, fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text("Payout: $rTxt", style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600))),
            const SizedBox(width: 16),
            Text("Vault: ${(c.budgetRemaining / BigInt.from(10).pow(18)).toStringAsFixed(2)} SOMI", style: const TextStyle(color: AppColors.textSub, fontSize: 13))
          ])
        ]),
        ElevatedButton.icon(onPressed: () => _copy(c.targetContract), icon: const Icon(Icons.link, size: 18), label: const Text("Copy Link"), style: ElevatedButton.styleFrom(backgroundColor: AppColors.textMain, foregroundColor: AppColors.bg, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))))
      ]),
    ));
  }
}

// ==============================================================
// 11. CHECKOUT SANDBOX (Network Testing)
// ==============================================================
class CheckoutScreen extends StatefulWidget {
  final String address;
  final Ethereum provider;
  final String initChainId;
  final String? refAddress;
  const CheckoutScreen({super.key, required this.address, required this.provider, required this.initChainId, this.refAddress});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> with Web3Utils {
  bool _isTransacting = false;
  String _status = "";
  String? _tx;
  bool _isFailedTx = false;

  @override
  void initState() {
    super.initState();
    _currentChainId = widget.initChainId;
  }

  Future<void> _buy() async {
    debugPrint("\n--- PURCHASE INITIATED ---");
    setState(() { _isTransacting = true; _tx = null; _isFailedTx = false; });
    
    if (!await ensureCorrectNetwork(widget.provider, context, (s) => setState(() => _status = s))) {
      setState(() => _isTransacting = false); return;
    }

    final p = BigInt.parse("10000000000000000"); // 0.01 SOMI
    final bal = await getBalance(widget.provider, widget.address);
    debugPrint("[Checkout] Required: $p Wei | Current: $bal Wei");
    if (bal < p) { 
      debugPrint("[Checkout] Insufficient SOMI.");
      setState(() { _isTransacting = false; _status = "Insufficient SOMI."; }); return; 
    }

    String ref = widget.refAddress ?? "0x0000000000000000000000000000000000000000";
    if (ref.length != 42) ref = "0x0000000000000000000000000000000000000000";
    debugPrint("[Checkout] Routing affiliate referrer: $ref");

    try {
      setState(() => _status = "Confirming in Wallet...");
      final payload = Web3Service.encodeBuyItem(_currentChainId, ref);
      final hexValue = "0x${p.toRadixString(16)}";
      
      debugPrint("[Checkout] Firing eth_sendTransaction...");
      final txHash = ((await widget.provider.request(RequestArguments(method: 'eth_sendTransaction'.toJS, params: [{'to': Web3Service.getMarketAddress(_currentChainId), 'from': widget.address, 'data': payload, 'value': hexValue, 'gas': '0x2dc6c0'}].jsify())).toDart) as JSString).toDart;
      
      debugPrint("[Checkout] Broadcasted. Hash: $txHash");
      setState(() => _status = "Confirming on-chain...");

      try {
        final success = await waitForReceipt(widget.provider, txHash);
        if (!success) {
          debugPrint("[Checkout] Transaction Reverted.");
          setState(() { _isFailedTx = true; _tx = txHash; });
          return;
        }
      } catch (pollErr) {
        debugPrint("[Checkout] Polling error swallowed: $pollErr");
      }

      debugPrint("[Checkout] CONFIRMED SUCCESS.");
      setState(() { _isFailedTx = false; _tx = txHash; });
    } catch (e) { 
      debugPrint("[Checkout] CRITICAL FAILURE: $e");
      String errMsg = "Transaction failed.";
      if (e.toString().contains("insufficient funds")) errMsg = "Transaction failed: Insufficient gas/funds.";
      else if (e.toString().contains("rejected")) errMsg = "Transaction rejected by user.";
      else errMsg = e.toString();
      setState(() => _status = errMsg); 
    } finally { 
      debugPrint("--- PURCHASE ENDED ---\n");
      setState(() => _isTransacting = false); 
    }
  }

  @override
  Widget build(BuildContext context) {
    String networkLabel = _currentChainId == '0xc487' ? "Mainnet" : "Testnet";
    return Scaffold(
      appBar: PreferredSize(preferredSize: const Size.fromHeight(70), child: Container(decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))), padding: const EdgeInsets.symmetric(horizontal: 40), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text("Checkout Sandbox", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textMain)), 
        Row(
          children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), decoration: BoxDecoration(color: _currentChainId == '0xc487' ? AppColors.primary.withOpacity(0.2) : Colors.orange.withOpacity(0.2), borderRadius: BorderRadius.circular(12)), child: Text(networkLabel, style: TextStyle(color: _currentChainId == '0xc487' ? AppColors.primary : Colors.orange, fontSize: 12, fontWeight: FontWeight.bold))),
            const SizedBox(width: 16),
            Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.border)), child: Text("${widget.address.substring(0,6)}...${widget.address.substring(38)}", style: const TextStyle(fontSize: 14, color: AppColors.textSub, fontFamily: 'monospace'))),
          ],
        )
      ]))),
      body: KeyboardScrollWrapper(controller: scrollController, child: SelectionArea(child: Center(child: DeFiCard(width: 450, padding: const EdgeInsets.all(40), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(height: 160, width: double.infinity, decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)), child: const Center(child: Icon(Icons.token, size: 64, color: AppColors.textMain))),
        const SizedBox(height: 32),
        const Text("Genesis Access Pass", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        const SizedBox(height: 8),
        const Text("Price: 0.01 SOMI", style: TextStyle(fontSize: 16, color: AppColors.textSub)),
        const SizedBox(height: 32),
        if (widget.refAddress != null) Padding(padding: const EdgeInsets.only(bottom: 24), child: Text("Referred by: ${widget.refAddress!.substring(0,6)}...${widget.refAddress!.substring(38)}", style: const TextStyle(color: AppColors.primary, fontSize: 12, fontFamily: 'monospace'))),
        
        if (_tx != null) ...[
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24), 
            decoration: BoxDecoration(
              color: _isFailedTx ? Colors.redAccent.withOpacity(0.1) : AppColors.success.withOpacity(0.1), 
              borderRadius: BorderRadius.circular(16), 
              border: Border.all(color: _isFailedTx ? Colors.redAccent.withOpacity(0.3) : AppColors.success.withOpacity(0.3))
            ),
            child: Column(children: [
              Icon(_isFailedTx ? Icons.error_outline : Icons.check_circle, color: _isFailedTx ? Colors.redAccent : AppColors.success, size: 40), const SizedBox(height: 12),
              Text(_isFailedTx ? "Transaction Reverted by EVM" : "Mint Successful!", style: TextStyle(color: _isFailedTx ? Colors.redAccent : AppColors.success, fontWeight: FontWeight.bold, fontSize: 20)), const SizedBox(height: 12),
              InkWell(
                onTap: () => web.window.open(getExplorerUrl(_currentChainId, _tx!), '_blank'),
                child: MouseRegion(cursor: SystemMouseCursors.click, child: Text("View on Explorer ↗\n${getExplorerUrl(_currentChainId, _tx!)}", style: const TextStyle(color: AppColors.primary, decoration: TextDecoration.underline, fontSize: 13, fontFamily: 'monospace', height: 1.5), textAlign: TextAlign.center)),
              ),
            ]),
          ).animate().fadeIn(),
        ] else ...[
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _isTransacting ? null : _buy, style: ElevatedButton.styleFrom(backgroundColor: AppColors.textMain, foregroundColor: AppColors.bg, padding: const EdgeInsets.symmetric(vertical: 24), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: _isTransacting ? Text(_status) : const Text("Mint Asset", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))))
        ]
      ]))))),
    );
  }
}