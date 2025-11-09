import 'package:flutter/material.dart';
import 'package:town_pass/util/tp_app_bar.dart';
import 'package:town_pass/util/tp_card.dart';
import 'package:town_pass/util/tp_colors.dart';
import 'package:town_pass/util/tp_text.dart';
import 'package:town_pass/gen/assets.gen.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

enum StepStatus { pending, loading, success, fail }

class StepInfo {
  String title;
  StepStatus status;
  StepInfo(this.title, {this.status = StepStatus.pending});
}

class AntiFraudView extends StatefulWidget {
  const AntiFraudView({super.key});

  @override
  State<AntiFraudView> createState() => _AntiFraudViewState();
}

class _AntiFraudViewState extends State<AntiFraudView> with TickerProviderStateMixin {
  // late AnimationController _wiggleController;
  // late Animation<double> _wiggleAnimation;
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late ListModel<String> _list;
  final TextEditingController _searchController = TextEditingController();
  int? _finalScore;
  String? _whySafe;
  String? _country;
  String? _whenCreate;
  String? _domainAge;

  late dynamic parseResult;

  bool _isChecking = false;

  // Example “5-point check” messages
  final List<StepInfo> _baseSteps = [
    StepInfo('NordVPN 檢測'),
    StepInfo('ML 檢測'),
    StepInfo('網站資訊檢測'),
  ];

  @override
  void initState() {
    super.initState();
    _list = ListModel<String>(
      listKey: _listKey,
      initialItems: <String>[],
      removedItemBuilder: _buildRemovedItem,
    );
    // _wiggleController = AnimationController(
    //   vsync: this,
    //   duration: const Duration(seconds: 1),
    // )..repeat(reverse: true); // oscillates back and forth
    //
    // // The angle in radians: -0.05 to +0.05 (around ±3 degrees)
    // _wiggleAnimation = Tween<double>(begin: -0.05, end: 0.05).animate(
    //   CurvedAnimation(parent: _wiggleController, curve: Curves.easeInOut),
    // );
  }

  @override
  void dispose() {
    // _wiggleController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final input = _searchController.text.trim();
    if (input.isEmpty || _isChecking) return;

    setState(() {
      _isChecking = true;
      _finalScore = null;
      _whySafe = null;
      _domainAge = null;
      _country = null;
      _whenCreate = null;
    });

    // Clear previous results and reset step statuses
    _list.clear();
    for (var s in _baseSteps) s.status = StepStatus.pending;

    // Show first 3 steps with loading spinner
    for (int i = 0; i < 3; i++) {
      _baseSteps[i].status = StepStatus.loading;
      _list.insert(_list.length, _baseSteps[i].title); // insert titles to AnimatedList
      setState(() {}); // rebuild so CardItem shows spinner
      await Future.delayed(const Duration(milliseconds: 600));
    }

    final uri = Uri.parse('http://140.115.238.230:8001/test_url');
    final headers = {'Content-Type': 'application/json'};
    final body = jsonEncode({'url': input});

    http.Response? response;
    dynamic parsed;

    try {
      response = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
    } on TimeoutException {
      // mark steps fail and show message
      for (int i = 0; i < 3; i++) {
        _baseSteps[i].status = StepStatus.fail;
      }
      _list.insert(_list.length, '❗ 錯誤：伺服器連線逾時（timeout）');
      setState(() {
        _isChecking = false;
      });
      return;
    } catch (e) {
      for (int i = 0; i < 3; i++) {
        _baseSteps[i].status = StepStatus.fail;
      }
      _list.insert(_list.length, '❗ 發生錯誤: ${e.toString()}');
      setState(() {
        _isChecking = false;
      });
      return;
    }

    if (response.statusCode != 200) {
      for (int i = 0; i < 3; i++) _baseSteps[i].status = StepStatus.fail;
      if(response.statusCode==500){
        _list.insert(_list.length, '❗ 輸入的可能不是合法網址');
      }
      else{_list.insert(_list.length, '❗ 伺服器錯誤：${response.statusCode}');}
      setState(() {
        _isChecking = false;
      });
      return;
    }

    // Try parse as JSON array
    try {
      parsed = jsonDecode(response.body);
    } catch (e) {
      // cannot parse
      for (int i = 0; i < 3; i++) _baseSteps[i].status = StepStatus.fail;
      _list.insert(_list.length, '⚠️ 無法解析回傳內容：${response.body}');
      setState(() {
        _isChecking = false;
      });
      return;
    }

    // parsed should be a List
    if (parsed is! List) {
      // fallback: show raw content
      for (int i = 0; i < 3; i++) _baseSteps[i].status = StepStatus.fail;
      _list.insert(_list.length, '回傳格式非預期：${parsed.toString()}');
      setState(() {
        _isChecking = false;
      });
      return;
    }

    int score=0;

    // ---------- Map parsed results to UI steps ----------
    // Expectation (based on your sample):
    // parsed[0] -> { "nordVPN": "unsafe" }
    // parsed[1] -> { "MLtest": "safe" }
    // parsed[2] -> { "is_edu": false, "is_fraud": false, "is_gov": false, "test_result": { ... } }

    parseResult=parsed;

    // Step 0: nordVPN
    try {
      final item0 = parsed.length > 0 ? parsed[0] : null;
      if (item0 is Map && item0.containsKey('nordVPN')) {
        final v = item0['nordVPN']?.toString().toLowerCase() ?? '';
        _baseSteps[0].status = (v == 'safe') ? StepStatus.success : StepStatus.fail;
        if(v=='safe')score+=25;
      } else {
        _baseSteps[0].status = StepStatus.fail;
      }
    } catch (e) {
      _baseSteps[0].status = StepStatus.fail;
    }
    setState(() {});

    try {
      final item0 = parsed.length > 0 ? parsed[1] : null;
      if (item0 is Map && item0.containsKey('MLtest')) {
        final v = item0['MLtest']?.toString().toLowerCase() ?? '';
        _baseSteps[1].status = (v == 'safe') ? StepStatus.success : StepStatus.fail;
        if(v=='safe')score+=25;
      } else {
        _baseSteps[1].status = StepStatus.fail;
      }
    } catch (e) {
      _baseSteps[1].status = StepStatus.fail;
    }
    setState(() {});

    await Future.delayed(const Duration(milliseconds: 350));

    try {
      final item0 = parsed.length > 0 ? parsed[2] : null;
      if (item0 is Map && item0.containsKey('is_fraud')) {
        final v = item0['is_fraud']?.toString().toLowerCase() ?? '';
        _baseSteps[2].status = (v == 'false') ? StepStatus.success : StepStatus.fail;
        if(v=='false'){
          score+=35;
        }
        if(item0['is_edu'].toString().toLowerCase()=='true') {
          score = 100;
          _whySafe="學術網路";
        }
        if(item0['is_gov'].toString().toLowerCase()=='true') {
          score = 100;
          _whySafe="政府網站";
        }

      } else {
        _baseSteps[2].status = StepStatus.fail;
        _whySafe="疑似詐騙網站";
      }
    } catch (e) {
      _baseSteps[2].status = StepStatus.fail;
    }
    setState(() {});

    print(score);
    // finished
    setState(() {
      _isChecking = false;
      _finalScore = score;
      _country = parsed[2]['test_result']['Country'];
      _whenCreate = parsed[2]['test_result']['Created'];
      _domainAge = parsed[2]['test_result']['Domain_age'];
    });


  }



  Widget _buildItem(BuildContext context, int index, Animation<double> animation) {
    // Match the base step by index if possible
    StepStatus status = StepStatus.loading;
    if (index < _baseSteps.length) status = _baseSteps[index].status;

    return CardItem(
      animation: animation,
      text: _list[index],
      status: status,
    );
  }


  Widget _buildRemovedItem(String item, BuildContext context, Animation<double> animation) {
    return CardItem(animation: animation, text: item);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TPAppBar(title: '詐騙網址查驗系統'),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Stack(
          children: [
            Column(
            children: [
              const TPText('網站安全查驗', style: TPTextStyles.h1SemiBold),
              const SizedBox(height: 30),
              SearchBar(
                backgroundColor: MaterialStateProperty.all<Color>(const Color(0xFFFFFFFF)),
                controller: _searchController,
                hintText: '輸入要查驗的網站',
                leading: const Icon(Icons.search),
                onSubmitted: (_) => _performSearch(),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _isChecking ? null : _performSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5ab4c5),
                  disabledBackgroundColor: const Color(0xFF9dbcc2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: Text(
                    _isChecking ? "檢查中..." : "送出",
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Expanded(
                child: AnimatedList(
                  key: _listKey,
                  initialItemCount: _list.length,
                  itemBuilder: _buildItem,
                ),
              ),
              _buildInfoCard(),
              // _buildScoreCard(),
            ],
          ),
            // Positioned(
            //   left: 16,
            //   bottom: 16,
            //   child: AnimatedBuilder(
            //     animation: _wiggleAnimation,
            //     builder: (context, child) {
            //       return Transform.rotate(
            //         angle: _wiggleAnimation.value,
            //         child: child,
            //       );
            //     },
            //     child: Image.asset(
            //       'assets/image/w1.png',
            //       width: 100,
            //       height: 100,
            //     ),
            //   ),
            // ),
          ],
        ),
      ),
    );
  }

  String _getFlagEmoji(String? countryCode) {
    // 如果 countryCode 是 null 或是長度不為 2，返回一個通用的地球 emoji
    if (countryCode == null || countryCode.length != 2) {
      return '🌍';
    }
    // 將字母轉換為大寫
    final String code = countryCode.toUpperCase();
    // 核心邏輯：'A' (ASCII 65) 對應到 'Regional Indicator Symbol Letter A' (Unicode 127462)
    // 偏移量 = 127462 - 65 = 127397
    final int first = code.codeUnitAt(0) - 65 + 127462;
    final int second = code.codeUnitAt(1) - 65 + 127462;
    // 將 Unicode 碼點轉換回字串
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  Widget _buildInfoCard() {
    // If there's no score, return an empty widget
    if (_finalScore == null) {
      return const SizedBox.shrink();
    }

    // Customize title, color, and icon based on the score
    String title;
    Color cardColor;
    Color textColor;
    IconData icon;

    if (_finalScore! >= 90) {
      title = '網站安全';
      cardColor = const Color(0xFFE8F5E9); // Light Green
      textColor = Colors.green.shade900;
      icon = Icons.verified_user;
    } else if (_finalScore! >= 85) {
      title = '基本安全但建議謹慎';
      cardColor = const Color(0xFFE8F5E9); // Light Yellow
      textColor = Colors.green.shade900;
      icon = Icons.warning_amber_rounded;
    } else if (_finalScore! >= 50) {
      title = '建議謹慎';
      cardColor = const Color(0xFFFFFDE7); // Light Yellow
      textColor = Colors.yellow.shade900;
      icon = Icons.warning_amber_rounded;
    } else {
      title = '高度風險';
      cardColor = const Color(0xFFFFEBEE); // Light Red
      textColor = Colors.red.shade900;
      icon = Icons.gpp_bad_rounded;
    }

    return Card(
      elevation: 4,
      color: cardColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(top: 16.0, bottom: 8.0), // Add some space
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Icon(icon, size: 40, color: textColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      Spacer(),
                      Text(
                        (_whySafe != null) ? _whySafe ?? "" : "",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '綜合安全評分: $_finalScore / 100',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),

                  // --- *** 新增的網域資訊 *** ---
                  // 只有在任何一項額外資訊存在時才顯示分隔線和內容
                  if (_country != null ||
                      _whenCreate != null ||
                      _domainAge != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
                      // 使用帶有透明度的文字顏色，使分隔線不那麼刺眼
                      child: Divider(color: textColor.withOpacity(0.4)),
                    ),

                    // 國家
                    if (_country != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          children: [
                            // 顯示國旗 Emoji
                            Text(
                              _getFlagEmoji(_country),
                              style: const TextStyle(fontSize: 20),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '國家: $_country', // 這裡顯示 "國家: TW"
                              style: TextStyle(
                                  fontSize: 15, color: Colors.black.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ),

                    // 創建日期
                    if (_whenCreate != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_outlined,
                                size: 16, color: Colors.black.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Text(
                              '創建日期: $_whenCreate',
                              style: TextStyle(
                                  fontSize: 15, color: Colors.black.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ),

                    // 網域年齡
                    if (_domainAge != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          children: [
                            Icon(Icons.hourglass_bottom_outlined,
                                size: 16, color: Colors.black.withOpacity(0.6)),
                            const SizedBox(width: 8),
                            Text(
                              '網域年齡: $_domainAge',
                              style: TextStyle(
                                  fontSize: 15, color: Colors.black.withOpacity(0.7)),
                            ),
                          ],
                        ),
                      ),
                  ],
                  // --- *** 資訊結束 *** ---
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ADD THIS NEW HELPER METHOD
  // Widget _buildScoreCard() {
  //   // If there's no score, return an empty widget
  //   if (_finalScore == null) {
  //     return const SizedBox.shrink();
  //   }
  //
  //   // Customize title, color, and icon based on the score
  //   String title;
  //   Color cardColor;
  //   Color textColor;
  //   IconData icon;
  //
  //   if (_finalScore! >= 90) {
  //     title = '網站安全';
  //     cardColor = const Color(0xFFE8F5E9); // Light Green
  //     textColor = Colors.green.shade900;
  //     icon = Icons.verified_user;
  //   }
  //   else if (_finalScore! >= 85) {
  //     title = '基本安全但建議謹慎';
  //     cardColor = const Color(0xFFE8F5E9); // Light Yellow
  //     textColor = Colors.green.shade900;
  //     icon = Icons.warning_amber_rounded;
  //   }
  //   else if (_finalScore! >= 50) {
  //     title = '建議謹慎';
  //     cardColor = const Color(0xFFFFFDE7); // Light Yellow
  //     textColor = Colors.yellow.shade900;
  //     icon = Icons.warning_amber_rounded;
  //   }
  //   else {
  //     title = '高度風險';
  //     cardColor = const Color(0xFFFFEBEE); // Light Red
  //     textColor = Colors.red.shade900;
  //     icon = Icons.gpp_bad_rounded;
  //   }
  //
  //   return Card(
  //     elevation: 4,
  //     color: cardColor,
  //     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  //     margin: const EdgeInsets.only(top: 16.0, bottom: 8.0), // Add some space
  //     child: Padding(
  //       padding: const EdgeInsets.all(16.0),
  //       child: Row(
  //         children: [
  //           Icon(icon, size: 40, color: textColor),
  //           const SizedBox(width: 16),
  //           Expanded(
  //             child: Column(
  //               crossAxisAlignment: CrossAxisAlignment.start,
  //               children: [
  //                 Row(
  //                   children: [
  //                     Text(
  //                       title,
  //                       style: TextStyle(
  //                         fontSize: 18,
  //                         fontWeight: FontWeight.bold,
  //                         color: textColor,
  //                       ),
  //                     ),
  //                     Spacer(),
  //                     Text(
  //                       (_whySafe!=null)?_whySafe??"":"",
  //                       style: TextStyle(
  //                         fontSize: 18,
  //                         fontWeight: FontWeight.bold,
  //                         color: textColor,
  //                       ),
  //                     ),
  //                   ],
  //                 ),
  //                 const SizedBox(height: 4),
  //                 Text(
  //                   '綜合安全評分: $_finalScore / 100',
  //                   style: TextStyle(
  //                     fontSize: 22,
  //                     fontWeight: FontWeight.w700,
  //                     color: Colors.black87,
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

}

/// A simple list model wrapper for AnimatedList
class ListModel<E> {
  ListModel({
    required this.listKey,
    required this.removedItemBuilder,
    Iterable<E>? initialItems,
  }) : _items = List<E>.from(initialItems ?? <E>[]);

  final GlobalKey<AnimatedListState> listKey;
  final RemovedItemBuilder<E> removedItemBuilder;
  final List<E> _items;

  AnimatedListState? get _animatedList => listKey.currentState;

  void insert(int index, E item) {
    _items.insert(index, item);
    _animatedList?.insertItem(index);
  }

  void clear() {
    while (_items.isNotEmpty) {
      removeAt(0);
    }
  }

  E removeAt(int index) {
    final E removedItem = _items.removeAt(index);
    _animatedList?.removeItem(index, (context, animation) {
      return removedItemBuilder(removedItem, context, animation);
    });
    return removedItem;
  }

  int get length => _items.length;
  E operator [](int index) => _items[index];
}

typedef RemovedItemBuilder<T> = Widget Function(T item, BuildContext context, Animation<double> animation);

class CardItem extends StatelessWidget {
  const CardItem({
    super.key,
    required this.animation,
    required this.text,
    this.status = StepStatus.loading,
  });

  final Animation<double> animation;
  final String text;
  final StepStatus status;

  Widget _statusIcon() {
    switch (status) {
      case StepStatus.success:
        return const Icon(Icons.check_circle, color: Colors.green);
      case StepStatus.fail:
        return const Icon(Icons.cancel, color: Colors.red);
      case StepStatus.loading:
        return const SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.blueGrey,
          ),
        );
      default:
        return const Icon(Icons.circle_outlined, color: Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: SizeTransition(
        sizeFactor: animation,
        axisAlignment: -1.0,
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                _statusIcon(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: Color(0xff3f3f3f),
                      fontSize: 18.0,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}



