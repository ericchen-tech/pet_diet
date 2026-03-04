import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:fl_chart/fl_chart.dart';

void main() => runApp(const PetDietApp());

class PetDietApp extends StatelessWidget {
  const PetDietApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 寵物營養家 Web',
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
  // 🔑 請填入您的 API Key
  static const String _apiKey = 'AIzaSyB8ITaax6N-mownvcQ3oT3wqbmvPJr8v8I';

  bool _isLoading = false;
  Map<String, dynamic>? _nutritionData;
  List<dynamic> _topIngredients = [];
  double _petWeight = 4.0;
  double _factor = 1.2;

  // ✅ 新增：用來控制是否開啟乾物質比 (DMB) 的開關
  bool _isDMB = false;

  final Map<String, double> _factorOptions = {
    "已結紮成貓 (1.2)": 1.2,
    "未結紮成貓 (1.4)": 1.4,
    "需減重貓 (1.0)": 1.0,
    "肥胖傾向 (0.8)": 0.8,
  };

  Future<void> _analyzeMultiImages() async {
    final picker = ImagePicker();
    final List<XFile> pickedImages = await picker.pickMultiImage();

    if (pickedImages.isEmpty) return;

    // 限制最多只取 2 張，避免 API 處理過載
    final List<XFile> images = pickedImages.take(2).toList();

    if (images.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("提示：建議上傳 2 張照片（成分清單 + 營養分析表）準確度會更高喔！")),
      );
    }

    setState(() {
      _isLoading = true;
      _nutritionData = null;
      _topIngredients = [];
      _isDMB = false; // 每次分析新照片時，預設關閉 DMB
    });

    try {
      final model = GenerativeModel(model: 'gemini-2.5-flash', apiKey: _apiKey);

      List<DataPart> imageParts = [];
      for (var img in images) {
        final bytes = await img.readAsBytes();
        imageParts.add(DataPart('image/jpeg', bytes));
      }

      const prompt = """
      請分析這 1~2 張寵物食品照片。資訊可能分散在不同照片。請整合後回傳唯一 JSON：
      {
        "protein": 數字, "fat": 數字, "fiber": 數字, "moisture": 數字, "ash": 數字, 
        "calcium": 數字, "phosphorus": 數字,
        "ingredients": [{"name": "成分名", "quality": "good/neutral/bad", "reason": "中文理由"}]
      }
      注意：數值欄位請只回傳純數字。
      """;

      final content = [
        Content.multi([TextPart(prompt), ...imageParts]),
      ];
      final response = await model.generateContent(content);

      String rText = response.text ?? "";
      String cleanJson = rText.replaceAll(RegExp(r'```json|```'), '').trim();

      final data = jsonDecode(cleanJson);

      setState(() {
        _nutritionData = data;
        _topIngredients = data['ingredients'] ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("分析失敗：$e")));
    }
  }

  double _safeNum(String key) {
    if (_nutritionData == null || _nutritionData![key] == null) return 0.0;
    var val = _nutritionData![key];
    if (val is num) return val.toDouble();
    String strVal = val.toString().replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(strVal) ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("AI寵物營養分析"), centerTitle: true),
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _analyzeMultiImages,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: Text(_isLoading ? "AI 綜合分析中..." : "上傳 2 張照片 (成分與標籤)"),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 60),
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (_nutritionData != null) ...[
                  const SizedBox(height: 15),

                  // ✅ 新增：DMB 切換開關 UI
                  Container(
                    decoration: BoxDecoration(
                      color: _isDMB ? Colors.teal.shade50 : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isDMB
                            ? Colors.teal.shade200
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: SwitchListTile(
                      title: const Text(
                        "切換為乾物質比 (DMB)",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: const Text(
                        "排除水分計算真實營養，適合評估罐頭",
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _isDMB,
                      activeColor: Colors.teal,
                      onChanged: (val) {
                        setState(() {
                          _isDMB = val;
                        });
                      },
                    ),
                  ),
                  const SizedBox(height: 15),

                  _buildHorizontalAnalysisPanel(),
                  _buildHealthAlerts(),
                  _buildIngredientExpansion(),
                  _buildFeedingCalculator(),
                ],
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.all(50),
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHorizontalAnalysisPanel() {
    double p = _safeNum('protein');
    double f = _safeNum('fat');
    double m = _safeNum('moisture');
    double fb = _safeNum('fiber');
    double ash = _safeNum('ash');
    double ca = _safeNum('calcium');
    double ph = _safeNum('phosphorus');
    double carb = max(0, 100 - p - f - fb - m - ash);
    double ratio = (ph > 0) ? ca / ph : 0.0;

    // ✅ 新增：如果開啟 DMB，計算放大係數 (排除水分)
    double dryFactor = (_isDMB && m < 100) ? 100 / (100 - m) : 1.0;

    // 計算顯示用的數值
    double displayP = p * dryFactor;
    double displayF = f * dryFactor;
    double displayCarb = carb * dryFactor;
    double displayFb = fb * dryFactor;
    double displayAsh = ash * dryFactor;
    double displayM = _isDMB ? 0.0 : m; // DMB 模式下水分為 0

    return Row(
      children: [
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 160,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 25,
                sections: [
                  _pieSection(displayP, Colors.redAccent),
                  _pieSection(displayF, Colors.orangeAccent),
                  _pieSection(displayCarb, Colors.blueAccent),
                  if (!_isDMB)
                    _pieSection(
                      displayM,
                      Colors.lightBlue.shade200,
                    ), // DMB 時不畫水分
                  _pieSection(displayFb, Colors.green.shade300),
                  _pieSection(displayAsh, Colors.grey.shade400),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.only(left: 15),
            child: Column(
              children: [
                _dataRow("蛋白質", displayP, Colors.redAccent),
                _dataRow("脂肪", displayF, Colors.orangeAccent),
                _dataRow("碳水(估)", displayCarb, Colors.blueAccent),
                _dataRow("纖維質", displayFb, Colors.green.shade300),
                _dataRow("灰分", displayAsh, Colors.grey.shade400),
                if (!_isDMB)
                  _dataRow(
                    "水分",
                    displayM,
                    Colors.lightBlue.shade200,
                  ), // DMB 時隱藏水分文字
                _dataRow(
                  "鈣磷比",
                  0,
                  Colors.teal,
                  customVal: "${ratio.toStringAsFixed(2)} : 1",
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHealthAlerts() {
    double p = _safeNum('protein');
    double f = _safeNum('fat');
    double fb = _safeNum('fiber');
    double m = _safeNum('moisture');
    double ash = _safeNum('ash');

    // ✅ 健康警示：碳水評估應一律採用 DMB 來判斷才準確 (尤其是罐頭)
    double carb = max(0, 100 - p - f - fb - m - ash);
    double carbDMB = (m < 100) ? carb * (100 / (100 - m)) : carb;

    if (carbDMB > 35) {
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
            const Icon(Icons.warning_amber_rounded, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "提醒：此食品碳水比例(DMB)偏高 (${carbDMB.toStringAsFixed(1)}%)，建議注意貓咪運動量。",
                style: const TextStyle(fontSize: 12, color: Colors.brown),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildIngredientExpansion() {
    return Container(
      margin: const EdgeInsets.only(top: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        leading: const Icon(Icons.list_alt, color: Colors.teal),
        title: const Text(
          "主要成分診斷",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        children: _topIngredients
            .map(
              (ing) => ListTile(
                leading: Icon(
                  ing['quality'] == 'good'
                      ? Icons.check_circle
                      : (ing['quality'] == 'bad' ? Icons.cancel : Icons.info),
                  color: ing['quality'] == 'good'
                      ? Colors.green
                      : (ing['quality'] == 'bad' ? Colors.red : Colors.orange),
                  size: 20,
                ),
                title: Text(
                  ing['name'] ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
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

  Widget _buildFeedingCalculator() {
    // ✅ 餵食量計算：必須使用包含水分的「原始數值 (As Fed)」，不受 DMB 切換影響
    double p = _safeNum('protein');
    double f = _safeNum('fat');
    double fb = _safeNum('fiber');
    double m = _safeNum('moisture');
    double ash = _safeNum('ash');
    double carb = max(0, 100 - p - f - fb - m - ash);

    // 計算每公斤代謝能 (kcal/kg)
    double kcalPerKg = (p * 3.5 + f * 8.5 + carb * 3.5) * 10;
    double der = (70 * pow(_petWeight, 0.75)) * _factor;
    double grams = kcalPerKg > 0 ? (der / kcalPerKg) * 1000 : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          const Divider(),
          const Text(
            "⚖️ 每日建議餵食量 (原物質)",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          Slider(
            value: _petWeight,
            min: 1,
            max: 15,
            divisions: 140,
            onChanged: (v) => setState(() => _petWeight = v),
          ),
          Text("貓咪體重: ${_petWeight.toStringAsFixed(1)} kg"),
          DropdownButton<double>(
            value: _factor,
            isExpanded: true,
            items: _factorOptions.entries
                .map(
                  (e) => DropdownMenuItem(value: e.value, child: Text(e.key)),
                )
                .toList(),
            onChanged: (v) => setState(() => _factor = v!),
          ),
          Text(
            "${grams.toStringAsFixed(1)} 克",
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataRow(String label, double val, Color color, {String? customVal}) {
    // 如果數值非常小(0)，就不顯示
    if (val == 0 && label != "鈣磷比" && label != "水分" && label != "碳水(估)")
      return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const Spacer(),
          Text(
            customVal ?? "${val.toStringAsFixed(1)}%",
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  PieChartSectionData _pieSection(double val, Color color) =>
      PieChartSectionData(
        color: color,
        value: val,
        radius: 40,
        showTitle: false,
      );
}
