import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// Peta rute sederhana memakai widget `CustomPaint`.
///
/// Sengaja tidak memakai tile peta dari internet supaya:
/// * aplikasi langsung jalan tanpa API key,
/// * tidak ada biaya/kebijakan tile yang dilanggar,
/// * ringan untuk ditampilkan di dalam feed.
///
/// Bila ingin peta ber-tile (OpenStreetMap, Mapbox, dsb.), tambahkan paket
/// `flutter_map` lalu ganti [CustomPaint] di bawah dengan `FlutterMap`.
class RouteMap extends StatelessWidget {
  const RouteMap({
    required this.polyline,
    this.points = const [],
    this.height = 180,
    this.strokeWidth = 4,
    this.showMarkers = true,
    this.backgroundColor = const Color(0xFF10161D),
    this.gridColor = const Color(0xFF1D252D),
    super.key,
  });

  /// Encoded polyline (presisi 5). Dipakai bila [points] kosong.
  final String polyline;

  /// Titik mentah; diprioritaskan bila tersedia.
  final List<LatLng> points;

  final double height;
  final double strokeWidth;
  final bool showMarkers;
  final Color backgroundColor;
  final Color gridColor;

  List<LatLng> get _coords =>
      points.isNotEmpty ? points : decodePolyline(polyline);

  @override
  Widget build(BuildContext context) {
    final coords = _coords;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: height,
        width: double.infinity,
        color: backgroundColor,
        child: coords.length < 2
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, color: Color(0xFF4A5560), size: 28),
                    SizedBox(height: 6),
                    Text(
                      'Rute tidak tersedia',
                      style: TextStyle(color: Color(0xFF8B98A5), fontSize: 12),
                    ),
                  ],
                ),
              )
            : CustomPaint(
                painter: _RoutePainter(
                  coords: coords,
                  strokeWidth: strokeWidth,
                  gridColor: gridColor,
                  showMarkers: showMarkers,
                ),
              ),
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.coords,
    required this.strokeWidth,
    required this.gridColor,
    required this.showMarkers,
  });

  final List<LatLng> coords;
  final double strokeWidth;
  final Color gridColor;
  final bool showMarkers;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    var minLat = coords.first.latitude, maxLat = coords.first.latitude;
    var minLon = coords.first.longitude, maxLon = coords.first.longitude;
    for (final c in coords) {
      minLat = c.latitude < minLat ? c.latitude : minLat;
      maxLat = c.latitude > maxLat ? c.latitude : maxLat;
      minLon = c.longitude < minLon ? c.longitude : minLon;
      maxLon = c.longitude > maxLon ? c.longitude : maxLon;
    }

    final spanLat = (maxLat - minLat).abs();
    final spanLon = (maxLon - minLon).abs();
    if (spanLat < 1e-9 && spanLon < 1e-9) return;

    const pad = 18.0;
    final w = size.width - pad * 2;
    final h = size.height - pad * 2;
    final scale =
        (spanLat > 1e-9 && spanLon > 1e-9) ? (w / spanLon < h / spanLat ? w / spanLon : h / spanLat) : (spanLat > 1e-9 ? h / spanLat : w / spanLon);

    final drawnW = spanLon * scale;
    final drawnH = spanLat * scale;
    final offX = pad + (w - drawnW) / 2;
    final offY = pad + (h - drawnH) / 2;

    Offset project(LatLng c) => Offset(
          offX + (c.longitude - minLon) * scale,
          // Latitude naik ke atas -> balik sumbu Y.
          offY + (maxLat - c.latitude) * scale,
        );

    final path = Path();
    final first = project(coords.first);
    path.moveTo(first.dx, first.dy);
    for (var i = 1; i < coords.length; i++) {
      final p = project(coords[i]);
      path.lineTo(p.dx, p.dy);
    }

    // Glow di belakang garis utama.
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFC5200).withValues(alpha: 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFF6B2C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (showMarkers) {
      final start = project(coords.first);
      final end = project(coords.last);
      canvas.drawCircle(start, 5, Paint()..color = const Color(0xFF2FB344));
      canvas.drawCircle(
        start,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      canvas.drawCircle(end, 5, Paint()..color = const Color(0xFFE5484D));
      canvas.drawCircle(
        end,
        5,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter old) =>
      old.coords != coords || old.strokeWidth != strokeWidth;
}

/// Decoder polyline (format Google) — dipakai untuk memuat rute dari server.
List<LatLng> decodePolyline(String encoded) {
  if (encoded.isEmpty) return const [];
  final coords = <LatLng>[];
  var index = 0, lat = 0, lon = 0;
  while (index < encoded.length) {
    var shift = 0, result = 0, b = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    shift = 0;
    result = 0;
    do {
      b = encoded.codeUnitAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    lon += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

    coords.add(LatLng(lat / 1e5, lon / 1e5));
  }
  return coords;
}
