import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: BitcoinScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class BitcoinScreen extends StatefulWidget {
  const BitcoinScreen({super.key});
  @override
  State<BitcoinScreen> createState() => _BitcoinScreenState();
}

class _BitcoinScreenState extends State<BitcoinScreen> {
  List<double> prices = [];
  List<DateTime> times = [];
  double currentPrice = 0;
  Timer? timer;

  int rollingWindow = 200;
  int predictionInterval = 15; // default 15 segundos
  final int limit = 600;
  final TextEditingController rollingController =
      TextEditingController(text: "200");

  final Map<int, String> stateNames = {
    0: "Baja suave",
    1: "Baja alta vol",
    2: "Subida suave",
    3: "Subida alta vol",
  };

  final Map<int, String> stateDescriptions = {
    0: "Precio baja suavemente, sin grandes movimientos.",
    1: "Precio baja, pero con movimientos bruscos (alta volatilidad).",
    2: "Precio sube suavemente, tendencia positiva moderada.",
    3: "Precio sube, pero con movimientos bruscos (alta volatilidad).",
  };

  @override
  void initState() {
    super.initState();
    fetchData();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => fetchData());
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> fetchData() async {
    final url =
        "https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&limit=$limit";
    final response = await http.get(Uri.parse(url));
    final data = jsonDecode(response.body);

    List<double> tempPrices = [];
    List<DateTime> tempTimes = [];

    for (var candle in data) {
      tempPrices.add(double.parse(candle[4]));
      tempTimes.add(DateTime.fromMillisecondsSinceEpoch(candle[0]));
    }

    setState(() {
      prices = tempPrices;
      times = tempTimes;
      currentPrice = prices.last;
    });
  }

  List<double> calculateReturns(List<double> prices) {
    List<double> returns = [];
    for (int i = 1; i < prices.length; i++) {
      returns.add((prices[i] - prices[i - 1]) / prices[i - 1]);
    }
    return returns;
  }

  double std(List<double> values) {
    if (values.isEmpty) return 0;
    double mean = values.reduce((a, b) => a + b) / values.length;
    double sum = values.map((v) {
      double diff = v - mean;
      return diff * diff;
    }).reduce((a, b) => a + b);
    return sqrt(sum / values.length);
  }

  void runPrediction() {
    if (prices.length < rollingWindow) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No hay suficientes datos")));
      return;
    }

    List<double> train = prices.sublist(prices.length - rollingWindow);
    List<double> returns = calculateReturns(train);

    List<double> vol = [];
    for (int i = 9; i < returns.length; i++) {
      vol.add(std(returns.sublist(i - 9, i)));
    }
    double volThreshold = vol.reduce((a, b) => a + b) / vol.length;

    List<int> states = [];
    for (int i = 10; i < train.length; i++) {
      double ret = returns[i - 1];
      double volatility = vol[i - 10];
      int direction = ret > 0 ? 1 : 0;
      int highVol = volatility > volThreshold ? 1 : 0;
      states.add(direction * 2 + highVol);
    }

    List<List<double>> matrix =
        List.generate(4, (_) => List.generate(4, (_) => 0.0));
    for (int i = 0; i < states.length - 1; i++) {
      matrix[states[i]][states[i + 1]] += 1;
    }
    for (int i = 0; i < 4; i++) {
      double rowSum = matrix[i].reduce((a, b) => a + b);
      if (rowSum != 0) {
        for (int j = 0; j < 4; j++) {
          matrix[i][j] /= rowSum;
        }
      }
    }

    int currentState = states.last;
    List<double> probabilities = matrix[currentState];
    int predictedNextState =
        probabilities.indexWhere((e) => e == probabilities.reduce(max));
    double btcCurrent = prices.last;
    double btcStartPrice = prices[prices.length - rollingWindow];

    double btcNext = btcCurrent;
    int realNextState = 0;
    bool hit = false;
    double btcChangePercent = 0;
    bool resultReady = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          if (!resultReady) {
            Timer(Duration(seconds: predictionInterval), () {
              btcNext = prices.last;
              double newReturn = (btcNext - btcCurrent) / btcCurrent;
              double newVol = std(returns.sublist(returns.length - 10));
              realNextState =
                  (newReturn > 0 ? 1 : 0) * 2 + (newVol > volThreshold ? 1 : 0);
              hit = predictedNextState == realNextState;
              btcChangePercent =
                  ((btcNext - btcStartPrice) / btcStartPrice) * 100;

              setStateDialog(() {
                resultReady = true;
              });
            });
          }

          return AlertDialog(
            title: const Text("Predicción Markov"),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Matriz de transición (filas: estado actual, columnas: siguiente)",
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    // Scroll horizontal para la matriz
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Table(
                        border: TableBorder.all(color: Colors.grey),
                        defaultColumnWidth: const FixedColumnWidth(70),
                        children: [
                          TableRow(
                            children: [
                              const SizedBox(),
                              ...List.generate(
                                4,
                                (j) => Center(
                                  child: Text(
                                    stateNames[j]!,
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          ...List.generate(4, (i) {
                            return TableRow(
                              children: [
                                Center(
                                  child: Text(
                                    stateNames[i]!,
                                    style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...List.generate(4, (j) {
                                  double value = matrix[i][j];
                                  return Container(
                                    color: Colors.orange.withOpacity(value),
                                    height: 25,
                                    child: Center(
                                      child: Text(
                                        value.toStringAsFixed(2),
                                        style: const TextStyle(fontSize: 9),
                                      ),
                                    ),
                                  );
                                }),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "🔹 Estado actual: ${stateNames[currentState]} (Estado $currentState)",
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      "🔹 Probable siguiente estado según matriz: ${stateNames[predictedNextState]} (Estado $predictedNextState)",
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      "🔹 Valor BTC al predecir: \$${btcCurrent.toStringAsFixed(2)}",
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      resultReady
                          ? "🔹 Valor BTC después de ${predictionInterval >= 60 ? (predictionInterval ~/ 60).toString() + ' min' : predictionInterval.toString() + ' s'}: \$${btcNext.toStringAsFixed(2)}"
                          : "⏳ Esperando resultado...",
                      style: TextStyle(
                          fontSize: 12,
                          color: resultReady
                              ? (hit ? Colors.green : Colors.redAccent)
                              : Colors.yellowAccent),
                    ),
                    if (resultReady)
                      Text(
                        "🔹 Resultado predicción: ${hit ? '✅ Cumplida' : '❌ Falló, estado real: ${stateNames[realNextState]} (Estado $realNextState)'}",
                        style: TextStyle(
                            fontSize: 12,
                            color: hit ? Colors.green : Colors.redAccent),
                      ),
                    const SizedBox(height: 5),
                    const Text(
                      "Explicación de los estados:",
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    ...List.generate(
                      4,
                      (i) => Text(
                        "$i: ${stateNames[i]} → ${stateDescriptions[i]}",
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cerrar")),
            ],
          );
        });
      },
    );
  }

  void simulateOperations() {
    if (prices.length < rollingWindow) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No hay suficientes datos")));
      return;
    }

    List<double> train = prices.sublist(prices.length - rollingWindow);
    List<double> returns = calculateReturns(train);

    List<double> vol = [];
    for (int i = 9; i < returns.length; i++) {
      vol.add(std(returns.sublist(i - 9, i)));
    }
    double volThreshold = vol.reduce((a, b) => a + b) / vol.length;

    List<int> states = [];
    for (int i = 10; i < train.length; i++) {
      double ret = returns[i - 1];
      double volatility = vol[i - 10];
      int direction = ret > 0 ? 1 : 0;
      int highVol = volatility > volThreshold ? 1 : 0;
      states.add(direction * 2 + highVol);
    }

    List<List<double>> matrix =
        List.generate(4, (_) => List.generate(4, (_) => 0.0));
    for (int i = 0; i < states.length - 1; i++) {
      matrix[states[i]][states[i + 1]] += 1;
    }
    for (int i = 0; i < 4; i++) {
      double rowSum = matrix[i].reduce((a, b) => a + b);
      if (rowSum != 0) {
        for (int j = 0; j < 4; j++) {
          matrix[i][j] /= rowSum;
        }
      }
    }

    List<Map<String, dynamic>> allPredictions = [];

    String formatInterval(int seconds) {
      if (seconds < 60) return "$seconds s";
      int min = seconds ~/ 60;
      int sec = seconds % 60;
      if (sec == 0) return "$min min";
      return "$min:${sec.toString().padLeft(2, '0')} min";
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(builder: (context, setStateDialog) {
          Future<void> nextPrediction(int op) async {
            int currentState = states.last;
            List<double> probabilities = matrix[currentState];
            int predictedNextState =
                probabilities.indexWhere((e) => e == probabilities.reduce(max));
            double btcCurrent = train.last;

            Map<String, dynamic> pred = {
              "op": op + 1,
              "currentState": currentState,
              "predictedNextState": predictedNextState,
              "btcCurrent": btcCurrent,
              "btcNext": btcCurrent,
              "realNextState": 0,
              "hit": false,
              "btcChangePercent": 0,
              "status": "Esperando resultado",
              "probability": matrix[currentState][predictedNextState],
            };

            allPredictions.add(pred);
            setStateDialog(() {});

            await Future.delayed(Duration(seconds: predictionInterval));

            double btcNext = prices.last;
            double newReturn = btcNext - btcCurrent;
            double newVol = std(returns.sublist(max(0, returns.length - 10)));
            int realNextState =
                (newReturn > 0 ? 1 : 0) * 2 + (newVol > volThreshold ? 1 : 0);

            bool hitDirection = (btcNext - btcCurrent) > 0
                ? predictedNextState ~/ 2 == 1
                : predictedNextState ~/ 2 == 0;

            double btcChangePercent =
                ((btcNext - btcCurrent) / btcCurrent) * 100;

            pred["btcNext"] = btcNext;
            pred["realNextState"] = realNextState;
            pred["hit"] = hitDirection;
            pred["btcChangePercent"] = btcChangePercent;
            pred["status"] = hitDirection ? "✅ Cumplida" : "❌ Falló";

            states.add(realNextState);
            train.add(btcNext);
            returns = calculateReturns(train);
            vol.add(std(returns.sublist(max(0, returns.length - 10))));

            setStateDialog(() {});
          }

          if (allPredictions.isEmpty) {
            Future.forEach(List.generate(10, (i) => i), (i) async {
              await nextPrediction(i);
            });
          }

          return AlertDialog(
            title: Text(
              "QUE PASARÍA SI HAGO 10 OPERACIONES EN OPCIONES BINARIAS/TRADING SCALPING CADA ${formatInterval(predictionInterval)}",
              style: const TextStyle(fontSize: 14),
            ),
            content: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.7),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: allPredictions.map((pred) {
                    Color color;
                    if (pred["status"] == "Esperando resultado") {
                      color = Colors.yellow;
                    } else if (pred["hit"]) {
                      color = Colors.green;
                    } else {
                      color = Colors.redAccent;
                    }

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Operación ${pred["op"]}",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                              "Estado actual: ${stateNames[pred["currentState"]]} (Estado ${pred["currentState"]})"),
                          Text(
                              "Predicción siguiente estado: ${stateNames[pred["predictedNextState"]]} (Estado ${pred["predictedNextState"]}) Probabilidad: ${(pred["probability"] * 100).toStringAsFixed(1)}%"),
                          Text(
                              "BTC al predecir: \$${pred["btcCurrent"].toStringAsFixed(2)}"),
                          Text(pred["status"] == "Esperando resultado"
                              ? "⏳ Esperando resultado..."
                              : "BTC después: \$${pred["btcNext"].toStringAsFixed(2)} (Δ ${pred["btcChangePercent"].toStringAsFixed(2)}%) ${pred["status"]}"),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cerrar")),
            ],
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.orange,
        toolbarHeight: 80, // más alto para que quepan los renglones
        title: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown, // ajusta automáticamente si es muy largo
            child: const Text(
              "Proyecto final BMA-22 Bot Bitcoin\nPredecir Alza o Baja del BTC\nUsando Cadenas de Markov",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18, // tamaño base, se escala si hace falta
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          Text(
            "BTCUSDT",
            style: const TextStyle(color: Colors.white, fontSize: 22),
          ),
          Text(
            currentPrice.toStringAsFixed(2),
            style: const TextStyle(
                color: Colors.green, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(
                      show: true, border: Border.all(color: Colors.grey)),
                  lineBarsData: [
                    LineChartBarData(
                      spots: prices.asMap().entries.map((e) {
                        return FlSpot(e.key.toDouble(), e.value);
                      }).toList(),
                      isCurved: true,
                      color: Colors.orange,
                      dotData: const FlDotData(show: true),
                    )
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 60,
                        interval: 2000,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toStringAsFixed(2),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index >= times.length) return const SizedBox();
                          int step = (prices.length / 6).ceil(); // máximo 6
                          if (index % step != 0) return const SizedBox();
                          DateTime time = times[index];
                          return Text(
                            "${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}",
                            style: const TextStyle(
                                color: Colors.white, fontSize: 10),
                          );
                        },
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      tooltipBgColor: Colors.black87,
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          int index = spot.x.toInt();
                          DateTime time = times[index];
                          return LineTooltipItem(
                            "BTC: \$${spot.y.toStringAsFixed(2)}\n${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}",
                            const TextStyle(color: Colors.white, fontSize: 12),
                          );
                        }).toList();
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: rollingController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: "Rolling",
                      labelStyle: const TextStyle(color: Colors.orange),
                      enabledBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.orange),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: const BorderSide(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                DropdownButton<int>(
                  value: predictionInterval,
                  dropdownColor: Colors.black,
                  style: const TextStyle(color: Colors.white),
                  items: const [
                    DropdownMenuItem(value: 15, child: Text("15 s")),
                    DropdownMenuItem(value: 30, child: Text("30 s")),
                    DropdownMenuItem(value: 60, child: Text("1 min")),
                    DropdownMenuItem(value: 90, child: Text("1:30 min")),
                    DropdownMenuItem(value: 120, child: Text("2 min")),
                    DropdownMenuItem(value: 300, child: Text("5 min")),
                    DropdownMenuItem(value: 600, child: Text("10 min")),
                    DropdownMenuItem(value: 3600, child: Text("1 h")),
                  ],
                  onChanged: (value) {
                    setState(() {
                      predictionInterval = value!;
                    });
                  },
                ),
                ElevatedButton(
                  onPressed: () {
                    int? inputRolling = int.tryParse(rollingController.text);
                    if (inputRolling != null && inputRolling > 0) {
                      setState(() {
                        rollingWindow = inputRolling;
                      });
                    }
                    runPrediction();
                  },
                  child: const Text("Predecir"),
                ),
                ElevatedButton(
                  onPressed: () {
                    int? inputRolling = int.tryParse(rollingController.text);
                    if (inputRolling != null && inputRolling > 0) {
                      setState(() {
                        rollingWindow = inputRolling;
                      });
                    }
                    simulateOperations();
                  },
                  child: const Text("¿Qué hubiera pasado?"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
