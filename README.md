# 📈 BTC Markov Trading App

Aplicación móvil desarrollada en **Flutter** que muestra el **precio de Bitcoin en tiempo real** y utiliza **Cadenas de Markov** para analizar la probabilidad de movimientos futuros del mercado.

La aplicación descarga datos desde **Binance**, calcula **retornos y volatilidad**, construye una **matriz de transición de Markov**, y predice el **estado más probable del mercado** en un intervalo de tiempo seleccionado.

El objetivo es analizar **si el mercado tiene mayor probabilidad de subir o bajar en el corto plazo** utilizando estadística de transiciones de estados.

---

# 🚀 Características

- 📊 Gráfico en tiempo real del precio de BTCUSDT  
- ⏱ Descarga automática de datos del mercado  
- 🔄 Actualización continua del precio  
- 🧠 Predicción usando **Cadenas de Markov**  
- 📉 Análisis de **retornos y volatilidad**  
- 🔮 Predicción de tendencia futura  
- 📊 Simulación de operaciones tipo **trading / scalping**  
- ⚙️ Configuración de **rolling window**  
- ⏱ Selección del intervalo de predicción  

---

# 📊 Gráfico del precio

La aplicación muestra un **gráfico interactivo del precio de Bitcoin** utilizando la librería:

```
fl_chart
```

El gráfico muestra:

- precio del BTC
- eje temporal
- puntos interactivos para ver precio exacto
- actualización automática del mercado

Los datos mostrados corresponden a **velas de 1 minuto**.

---

# ⏱ Datos del mercado (API Binance)

La aplicación obtiene datos desde la API pública de Binance.

Endpoint utilizado:

```
https://api.binance.com/api/v3/klines
```

Parámetros usados:

```
symbol=BTCUSDT
interval=1m
limit=600
```

Esto descarga:

```
600 velas de 1 minuto ≈ 10 horas de datos
```

En el código:

```dart
final url =
"https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1m&limit=$limit";
```

Los datos se actualizan automáticamente cada **10 segundos**:

```dart
Timer.periodic(Duration(seconds: 10), (_) => fetchData());
```

---

# 🔄 Rolling Window

El modelo no utiliza todo el histórico de datos.

Utiliza una **ventana deslizante (Rolling Window)**.

Esto significa que el algoritmo analiza **solo los últimos N datos del mercado**.

Por defecto:

```
rollingWindow = 200
```

Pero el usuario puede modificarlo desde la interfaz.

Ejemplo:

```
rolling = 200
→ se analizan los últimos 200 minutos de precio
```

Implementación en el código:

```dart
List<double> train = prices.sublist(prices.length - rollingWindow);
```

Ventajas del rolling window:

- el modelo se adapta al mercado reciente
- evita usar datos antiguos irrelevantes
- permite probar diferentes horizontes de análisis

---

# 📉 Cálculo de Retornos

El modelo no utiliza precios directamente.

Primero calcula **retornos porcentuales**.

Fórmula:

```
return = (precio_actual - precio_anterior) / precio_anterior
```

En el código:

```dart
returns.add((prices[i] - prices[i - 1]) / prices[i - 1]);
```

Los retornos permiten medir:

- dirección del movimiento
- intensidad del cambio

---

# 🌪 Cálculo de Volatilidad

La volatilidad se calcula utilizando la **desviación estándar de los retornos**.

Para cada punto se calcula la volatilidad de los **últimos 10 retornos**.

Implementación:

```dart
std(returns.sublist(i - 9, i))
```

Luego se calcula un **threshold promedio de volatilidad**:

```dart
double volThreshold = vol.reduce((a, b) => a + b) / vol.length;
```

Esto permite clasificar el mercado en:

```
baja volatilidad
alta volatilidad
```

---

# 🧠 Estados del Mercado

El modelo define **4 estados del mercado** combinando:

- dirección del precio
- volatilidad

Estados definidos:

| Estado | Significado |
|------|------|
| 0 | Baja suave |
| 1 | Baja con alta volatilidad |
| 2 | Subida suave |
| 3 | Subida con alta volatilidad |

En el código:

```dart
int direction = ret > 0 ? 1 : 0;
int highVol = volatility > volThreshold ? 1 : 0;

state = direction * 2 + highVol;
```

Esto genera automáticamente los 4 estados posibles.

---

# 🔢 Construcción de la Matriz de Markov

Una vez obtenida la secuencia de estados:

```
[2,2,3,1,0,2,3,3,1...]
```

Se cuentan las transiciones entre estados.

Ejemplo:

```
2 → 2
2 → 3
3 → 1
1 → 0
```

En el código:

```dart
matrix[states[i]][states[i+1]] += 1;
```

Esto genera una **matriz de transición 4x4**.

Luego se normaliza para convertir los conteos en probabilidades:

```dart
matrix[i][j] /= rowSum;
```

Ejemplo de matriz resultante:

| Estado actual | 0 | 1 | 2 | 3 |
|---|---|---|---|---|
| 0 | 0.30 | 0.20 | 0.40 | 0.10 |
| 1 | 0.25 | 0.35 | 0.20 | 0.20 |
| 2 | 0.15 | 0.10 | 0.50 | 0.25 |
| 3 | 0.20 | 0.30 | 0.25 | 0.25 |

Cada fila representa:

```
Probabilidad del siguiente estado dado el estado actual
```

---

# 🔮 Predicción del siguiente estado

Se obtiene el **estado actual del mercado**:

```dart
int currentState = states.last;
```

Luego se revisa la fila correspondiente de la matriz.

Se selecciona el estado con **mayor probabilidad**:

```dart
probabilities.indexWhere((e) => e == probabilities.reduce(max));
```

Esto genera la predicción del modelo.

---

# ⏱ Intervalo de Predicción

El usuario puede elegir cuánto tiempo esperar para validar la predicción.

Opciones disponibles:

```
15 segundos
30 segundos
1 minuto
1:30 minutos
2 minutos
5 minutos
10 minutos
1 hora
```

Después de ese tiempo la aplicación compara:

```
precio al momento de la predicción
vs
precio actual
```

y determina si la predicción fue correcta.

---

# 📊 Simulación de Operaciones

La app incluye una función llamada:

```
¿Qué hubiera pasado?
```

Esta función simula **10 operaciones consecutivas** usando el modelo.

Cada operación realiza:

1. Predicción del siguiente estado
2. Espera del intervalo seleccionado
3. Comparación con el movimiento real
4. Evaluación si la predicción fue correcta

Esto permite simular escenarios de:

```
trading
scalping
opciones binarias
```

---

# 🖥 Interfaz de Usuario

La interfaz incluye:

- gráfico del precio en tiempo real
- precio actual de BTC
- selector de rolling window
- selector de intervalo de predicción
- botón **Predecir**
- botón **¿Qué hubiera pasado?**

También se muestra:

- matriz de Markov
- estado actual
- estado predicho
- resultado de la predicción
- explicación de cada estado

---

# 📦 Dependencias

Agregar en `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.0.0
  fl_chart: ^0.66.0
```

Instalar dependencias:

```
flutter pub get
```

---

# ▶️ Ejecutar el proyecto

Clonar repositorio:

```
git clone https://github.com/tuusuario/btc_markov_app.git
```

Entrar al proyecto:

```
cd btc_markov_app
```

Instalar dependencias:

```
flutter pub get
```

Ejecutar app:

```
flutter run
```

---

# 📚 Posibles mejoras futuras

El modelo puede mejorarse integrando:

- redes neuronales (LSTM)
- modelos híbridos Markov + Machine Learning
- indicadores técnicos (RSI, MACD)
- volumen y número de trades
- datos de order book
- modelos de volatilidad como **GARCH**
- aprendizaje automático para optimizar estados

---

# ⚠️ Advertencia

Este proyecto es **educativo y experimental**.

Las cadenas de Markov **no garantizan predicciones correctas** en mercados financieros.

El trading con criptomonedas implica **alto riesgo**.

Este proyecto **no constituye asesoría financiera**.

---

# 👨‍💻 Autor

Proyecto desarrollado en **Flutter + Dart** como aplicación experimental de análisis de mercado utilizando **Cadenas de Markov** aplicadas al precio de Bitcoin.
