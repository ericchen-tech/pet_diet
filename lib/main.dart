import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

void main() => runApp(const PetDietApp());

class PetDietApp extends StatelessWidget {
  const PetDietApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 寵物營養分析',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      home: const DietScreen(),
    );
  }
}

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});
  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  String _userApiKey = '';
  bool _isLoading = false;
  Map<String, dynamic>? _nutritionData;
  List<dynamic> _topIngredients = [];
  String _deepAnalysisText = "";

  double _totalPrice = 0.0;
  double _inputWeight = 1.0;
  String _weightUnit = 'kg';
  double _petWeight = 5.0;
  bool _isCat = true;
  double _factor = 1.2;
  double _wetFoodRatio = 0.5;
  bool _isDMB = false;

  final Map<String, double> _catFactors = {
    "節育成貓 (1.2)": 1.2,
    "未節育成貓 (1.4)": 1.4,
    "活動力低 (1.0)": 1.0,
    "減重 (0.8)": 0.8,
  };
  final Map<String, double> _dogFactors = {
    "節育成犬 (1.6)": 1.6,
    "未節育成犬 (1.8)": 1.8,
    "活動力低 (1.2)": 1.2,
    "減重 (1.0)": 1.0,
  };

  Future<void> _analyzeMultiImages() async {
    if (_userApiKey.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("⚠️ 請在上方輸入您的 API Key")));
      return;
    }
    final picker = ImagePicker();
    final List<XFile> pickedImages = await picker.pickMultiImage();
    if (pickedImages.isEmpty) return;

    setState(() {
      _isLoading = true;
      _nutritionData = null;
      _topIngredients = [];
      _deepAnalysisText = "正在解析成分並生成診斷報告...";
    });

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _userApiKey.trim(),
      );
      List<DataPart> imageParts = [];
      for (var img in pickedImages.take(2)) {
        final bytes = await img.readAsBytes();
        imageParts.add(DataPart('image/jpeg', bytes));
      }

      // ✅ 極度強化的 Prompt，確保 AI 不會漏掉主要成分欄位
      final prompt = """
      你現在是資深寵物營養師，請辨識照片數據並回傳單一 JSON。
      【重要：必須包含 deep_analysis 與 ingredients 兩個欄位】
      JSON 格式要求：
      {
        "protein": 數字, "fat": 數字, "fiber": 數字, "moisture": 數字, "ash": 數字, 
        "calcium": 數字, "phosphorus": 數字,
        "ingredients": [
          {"name": "成分1名稱", "quality": "good", "reason": "說明"},
          {"name": "成分2名稱", "quality": "bad", "reason": "說明"}
        ],
        "deep_analysis": "請針對比例與成分寫下至少 150 字的專業分析。"
      }
      若標籤無灰分請回傳 0。
      """;

      final response = await model.generateContent([
        Content.multi([TextPart(prompt), ...imageParts]),
      ]);
      String cleanJson = (response.text ?? "")
          .replaceAll(RegExp(r'```json|```'), '')
          .trim();
      final data = jsonDecode(cleanJson);

      setState(() {
        _nutritionData = data;
        // ✅ 確保抓取 ingredients 欄位
        _topIngredients = data['ingredients'] ?? [];
        _deepAnalysisText = data['deep_analysis'] ?? "AI 未能產出診斷文字，請重新上傳照片。";
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("分析失敗，可能是配額限制或格式錯誤：$e")));
    }
  }

  double _calculatePricePerKg() {
    double weightInKg = (_weightUnit == 'lb')
        ? _inputWeight * 0.4536
        : (_weightUnit == 'g')
        ? _inputWeight / 1000
        : _inputWeight;
    return weightInKg <= 0 ? 0 : _totalPrice / weightInKg;
  }

  double _safeNum(String key) {
    if (_nutritionData == null || _nutritionData![key] == null) return 0.0;
    var val = _nutritionData![key];
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString().replaceAll(RegExp(r'[^0-9.]'), '')) ??
        0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI 寵物營養分析"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSecurityPanel(),
            _buildSpeciesToggle(),
            const SizedBox(height: 15),
            _buildPetConditionCard(),
            const SizedBox(height: 15),
            _buildFoodPriceCard(),
            const SizedBox(height: 15),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _analyzeMultiImages,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_isLoading ? "分析中..." : "上傳照片"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 60),
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
            ),
            if (_nutritionData != null) ...[
              const SizedBox(height: 20),
              _buildDeepAnalysisCard(), // [AI 成分診斷]
              const SizedBox(height: 15),
              _buildDMBToggle(),
              _buildHorizontalAnalysisPanel(),
              _buildCPValueRow(),
              _buildHealthAlerts(),
              _buildIngredientExpansion(), // 主要成分診斷 (清單)
              _buildResultSummaryCard(),
            ],
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(50),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }

  // ✅ 變色圖示切換
  Widget _buildSpeciesToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _speciesBtn(
          "貓咪",
          FontAwesomeIcons.cat,
          _isCat,
          () => setState(() {
            _isCat = true;
            _factor = 1.2;
          }),
        ),
        const SizedBox(width: 15),
        _speciesBtn(
          "狗狗",
          FontAwesomeIcons.dog,
          !_isCat,
          () => setState(() {
            _isCat = false;
            _factor = 1.6;
          }),
        ),
      ],
    );
  }

  Widget _speciesBtn(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 25),
        decoration: BoxDecoration(
          color: isActive ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: isActive ? Colors.teal : Colors.grey),
        ),
        child: Row(
          children: [
            FaIcon(
              icon,
              color: isActive ? Colors.white : Colors.grey,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPetConditionCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assignment_ind, size: 18, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                "寵物狀況與餵食分配設定",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<double>(
            value: _factor,
            decoration: const InputDecoration(
              labelText: "需求因子 (活動量)",
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: (_isCat ? _catFactors : _dogFactors).entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.value,
                    child: Text(e.key, style: const TextStyle(fontSize: 13)),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _factor = v!),
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '體重 (kg)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (val) =>
                      setState(() => _petWeight = double.tryParse(val) ?? 5.0),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "熱量分配：此主食佔 ${(_wetFoodRatio * 100).toInt()}%",
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Slider(
                      value: _wetFoodRatio,
                      min: 0,
                      max: 1.0,
                      divisions: 10,
                      onChanged: (v) => setState(() => _wetFoodRatio = v),
                      activeColor: Colors.teal,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFoodPriceCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shopping_bag, size: 18, color: Colors.teal),
              SizedBox(width: 8),
              Text(
                "飼料或罐頭資訊設定",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '總價格',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (val) =>
                      setState(() => _totalPrice = double.tryParse(val) ?? 0.0),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: '重量',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (val) => setState(
                    () => _inputWeight = double.tryParse(val) ?? 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              DropdownButton<String>(
                value: _weightUnit,
                items: ['kg', 'lb', 'g']
                    .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                    .toList(),
                onChanged: (val) => setState(() => _weightUnit = val!),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalAnalysisPanel() {
    double p = _safeNum('protein'),
        f = _safeNum('fat'),
        m = _safeNum('moisture'),
        fb = _safeNum('fiber');
    double rawAsh = _safeNum('ash'),
        ca = _safeNum('calcium'),
        ph = _safeNum('phosphorus');

    // ✅ 智慧灰分修正：解決 DMB 40.9% 異常
    double ashDefault = (m > 20) ? 2.0 : 9.0;
    double ash = (rawAsh == 0) ? ashDefault : rawAsh;

    double carb = max(0, 100 - p - f - fb - m - ash);
    double dryFactor = (_isDMB && m < 100) ? 100 / (100 - m) : 1.0;
    double ratioVal = (ph > 0) ? (ca / ph) : 0.0;
    String ratioText = (ph > 0) ? "${ratioVal.toStringAsFixed(2)} : 1" : "N/A";
    Color ratioColor = (ratioVal >= 1.1 && ratioVal <= 1.4)
        ? Colors.green
        : Colors.orange;

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sections: [
                  _pieSection(p * dryFactor, Colors.redAccent),
                  _pieSection(f * dryFactor, Colors.orangeAccent),
                  _pieSection(carb * dryFactor, Colors.blueAccent),
                  if (!_isDMB) _pieSection(m, Colors.lightBlue.shade200),
                  _pieSection(fb * dryFactor, Colors.green.shade300),
                  _pieSection(ash * dryFactor, Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Column(
            children: [
              _dataRow("蛋白質", p * dryFactor, Colors.redAccent),
              _dataRow("脂肪", f * dryFactor, Colors.orangeAccent),
              _dataRow("碳水(估)", carb * dryFactor, Colors.blueAccent),
              _dataRow("纖維", fb * dryFactor, Colors.green.shade300),
              _dataRow(
                rawAsh == 0 ? "灰分(未提供預設${ashDefault.toInt()}%)" : "灰分",
                ash * dryFactor,
                Colors.grey.shade400,
              ),
              _dataRow("鈣磷比", 0, ratioColor, customVal: ratioText),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIngredientExpansion() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      child: ExpansionTile(
        title: const Text(
          "主要成分診斷",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        // ✅ 加入防呆提示，避免 AI 沒傳回 ingredients 時顯示全白
        children: _topIngredients.isEmpty
            ? [
                const ListTile(
                  title: Text(
                    "主要成分分析由 AI 產出中，請查閱上方診斷報告。",
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ]
            : _topIngredients
                  .map(
                    (ing) => ListTile(
                      leading: Icon(
                        ing['quality'] == 'good'
                            ? Icons.check_circle
                            : (ing['quality'] == 'bad'
                                  ? Icons.warning
                                  : Icons.info),
                        color: ing['quality'] == 'good'
                            ? Colors.green
                            : (ing['quality'] == 'bad'
                                  ? Colors.red
                                  : Colors.orange),
                      ),
                      title: Text(
                        ing['name'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        ing['reason'] ?? '',
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  )
                  .toList(),
      ),
    );
  }

  Widget _buildResultSummaryCard() {
    double p = _safeNum('protein'),
        f = _safeNum('fat'),
        m = _safeNum('moisture'),
        fb = _safeNum('fiber');
    double ash = (_safeNum('ash') == 0)
        ? ((m > 20) ? 2.0 : 9.0)
        : _safeNum('ash');
    double carb = max(0, 100 - p - f - fb - m - ash);
    double kcalPerKg = (p * 3.5 + f * 8.5 + carb * 3.5) * 10;
    double rer = 70 * pow(_petWeight, 0.75).toDouble();
    double der = rer * _factor;
    double currentFoodGrams = kcalPerKg > 0
        ? ((der * _wetFoodRatio) / kcalPerKg) * 1000
        : 0;
    double dailyCost = currentFoodGrams * (_calculatePricePerKg() / 1000.0);

    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("建議餵食量 (以此為例)"),
              Text(
                "${currentFoodGrams.toStringAsFixed(1)} 克",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("預估伙食費 (每日)"),
              Text(
                "${dailyCost.toStringAsFixed(1)} 元",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCPValueRow() {
    double pricePerGram = _calculatePricePerKg() / 1000.0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            "1克單價：",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          Text(
            "${pricePerGram.toStringAsFixed(3)} 元",
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeepAnalysisCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.teal.shade200),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        leading: const Icon(Icons.analytics, color: Colors.teal),
        title: const Text(
          "[AI 成分診斷]",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _deepAnalysisText,
              style: const TextStyle(
                fontSize: 13,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthAlerts() {
    double p = _safeNum('protein'),
        f = _safeNum('fat'),
        fb = _safeNum('fiber'),
        m = _safeNum('moisture');
    double ash = (_safeNum('ash') == 0)
        ? ((m > 20) ? 2.0 : 9.0)
        : _safeNum('ash');
    double carbDMB = (m < 100)
        ? (100 - p - f - fb - m - ash) * (100 / (100 - m))
        : 0;
    double threshold = _isCat ? 25.0 : 50.0;
    if (carbDMB > threshold) {
      return Container(
        margin: const EdgeInsets.only(top: 15),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "⚠️ 提醒：此食品碳水比例(DMB)對${_isCat ? '貓' : '狗'}來說偏高 (${carbDMB.toStringAsFixed(1)}%)。",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildSecurityPanel() {
    return Container(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        decoration: const InputDecoration(
          labelText: 'Gemini API Key',
          border: OutlineInputBorder(),
          prefixIcon: Icon(Icons.key),
          isDense: true,
        ),
        obscureText: true,
        onChanged: (val) => _userApiKey = val,
      ),
    );
  }

  Widget _buildDMBToggle() {
    return SwitchListTile(
      title: const Text("切換為乾物質比 (DMB)"),
      value: _isDMB,
      onChanged: (val) => setState(() => _isDMB = val),
    );
  }

  Widget _dataRow(String label, double val, Color color, {String? customVal}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12)),
            const Spacer(),
            Text(
              customVal ?? "${val.toStringAsFixed(1)}%",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      );
  PieChartSectionData _pieSection(double val, Color color) =>
      PieChartSectionData(
        color: color,
        value: val,
        radius: 40,
        showTitle: false,
      );
}
