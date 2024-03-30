import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Environment {
  static const apiKey = String.fromEnvironment('GOOGLE_MAPS_KEY');
}

Future<PermissionStatus> requestLocationPermission() async {
  var status = await Permission.location.request();
  return status;
}

void main() {
  runApp(const MyApp());
  requestLocationPermission();
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bus Lines',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.grey,
            brightness: Brightness.light),
        useMaterial3: true,
      ),
      home: const MainView(title: 'Bus Lines'),
      debugShowCheckedModeBanner: false,
    );
  }
}

Future<List<BusLine>> fetchBusLines() async {
  List<BusStop> stops = [];
  const url = "https://www.cs.virginia.edu/~pm8fc/busses/busses.json";
  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    final stopsData = data['stops'] ?? [];
    final routesData = data['routes'] ?? [];

    for (var route in routesData) {
      var routeStops = route["stops"] ?? [];

      for (var stopId in routeStops) {
        var stopData = stopsData.firstWhere((stop) =>
        stop["id"] == stopId, orElse: () => null);

        if (stopData != null) {
          stops.add(BusStop.fromJson(stopData, route["id"]));
        }
      }
    }

    List<BusLine> busLines = [];
    final linesData = data['lines'] ?? [];

    try {
      for (var line in linesData) {
        var lineStops = stops.where((stop) =>
        stop.routeId == line["id"]).toList();

        if (lineStops.isEmpty) {
          print("No stops for: ${line["id"]}");
          continue;
        }

        busLines.add(BusLine.fromJson(line, lineStops));
      }

      print("Completed Loop successfully.");
    } catch (e) {
      print("An exception occurred: $e");
    }
    return busLines;
  } else {
    throw Exception('Bus Lines: Failed to Load');
  }
}

class BusLine {
  final String longName;
  final String textColor;
  final List<double> bounds;
  final List<BusStop> stops;

  BusLine({
    required this.longName, required this.textColor,
    required this.bounds, required this.stops,
  });

  factory BusLine.fromJson(Map<String, dynamic> json, List<BusStop> stops) {
    return BusLine(
      longName: json['long_name'],
      textColor: json['text_color'],
      bounds: List<double>.from(json['bounds']),
      stops: stops,
    );
  }
}

class BusStop {
  final String code;
  final String description;
  final int id;
  final List<double> position;
  final String url;
  final int routeId;
  final String locType;
  final String name;
  final int? mainId;

  BusStop({
    required this.code, required this.description,
    required this.id, required this.position,
    required this.url, required this.routeId,
    required this.locType, required this.name,
    this.mainId,
  });

  factory BusStop.fromJson(Map<String, dynamic> json, int routeId) {
    return BusStop(
      code: json['code'],
      description: json['description'],
      id: json['id'],
      position: List<double>.from(json['position']),
      url: json['url'],
      routeId: routeId,
      locType: json['location_type'],
      name: json['name'],
      mainId: json['parent_station_id'],
    );
  }
}

class FavoritesManager {
  static const _favoritesKey = 'favorites';

  static Future<void> favorites(String busLineName) async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList(_favoritesKey) ?? [];

    if (favs.contains(busLineName)) {
      favs.remove(busLineName);
    }
    else {
      favs.add(busLineName);
    }
    await prefs.setStringList(_favoritesKey, favs);
  }

  static Future<Set<String>> getFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favs = prefs.getStringList(_favoritesKey);

    return favs?.toSet() ?? {};
  }
}

class MainView extends StatefulWidget {
  const MainView({super.key, required this.title});
  final String title;

  @override
  State<MainView> createState() => _MainViewState();
}

class _MainViewState extends State<MainView> {
  Future<List<BusLine>> fetchSortBusLines() async {
    final busLines = await fetchBusLines();
    final favs = await FavoritesManager.getFavorites();

    final Map<String, bool> favMap = {};
    for (var busLine in busLines) {
      favMap[busLine.longName] = favs.contains(busLine.longName);
    }

    busLines.sort((BusLine a, BusLine b) {
      final bool isAFav = favMap[a.longName] ?? false;
      final bool isBFav = favMap[b.longName] ?? false;

      if (isAFav == isBFav) {
        return a.longName.compareTo(b.longName);
      }
      return isAFav ? -1 : 1;
    });

    return busLines;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .inversePrimary,
        title: Text(widget.title),
      ),
      body: FutureBuilder<List<BusLine>>(
        future: fetchSortBusLines(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }
          if (snapshot.hasData) {
            final busLines = snapshot.data!;
            return ListView.separated(
              itemCount: busLines.length,
              separatorBuilder: (_, __) => Divider(height: 1, thickness: 1),
              itemBuilder: (context, index) {
                final busLine = busLines[index];
                return DecoratedBox(
                  decoration: BoxDecoration(
                      color: Color(int.parse('0xFF${busLine.textColor}'))),
                  child: ListTile(
                    title: Text(
                      busLine.longName,
                      style: TextStyle(color: Colors.black),
                    ),
                    trailing: FutureBuilder<Set<String>>(
                      future: FavoritesManager.getFavorites(),
                      builder: (context, favoriteSnapshot) {
                        if (favoriteSnapshot.hasData) {
                          final isFavorite = favoriteSnapshot.data!.contains(
                              busLine.longName);
                          return IconButton(
                            icon: Icon(
                              isFavorite ? Icons.star : Icons.star_border,
                              color: Colors.black,
                            ),
                            onPressed: () async {
                              await FavoritesManager.favorites(
                                  busLine.longName);
                              setState(() {});
                            },
                          );
                        }
                        return SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.0),
                        );
                      },
                    ),
                    onTap: () =>
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (context) =>
                              busLineMap(busLine: busLine)),
                        ),
                  ),
                );
              },
            );
          }
          return Center(child: CircularProgressIndicator());
        },
      ),
    );
  }
}

class busLineMap extends StatefulWidget {
  final BusLine busLine;

  const busLineMap({Key? key, required this.busLine}) : super(key: key);

  @override
  _UnifiedBusLineMapState createState() => _UnifiedBusLineMapState();
}

class _UnifiedBusLineMapState extends State<busLineMap> {
  late GoogleMapController mapController;
  final Set<Marker> _markers = {};

  void _onMapCreated(GoogleMapController controller) {
    mapController = controller;
    _setMapBounds();
    _addBusStopMarkers();
  }

  void _setMapBounds() {
    final LatLngBounds bounds = LatLngBounds(
      southwest: LatLng(widget.busLine.bounds[0], widget.busLine.bounds[1]),
      northeast: LatLng(widget.busLine.bounds[2], widget.busLine.bounds[3]),
    );
    mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  void _addBusStopMarkers() {
    for (var busStop in widget.busLine.stops) {
      _markers.add(
        Marker(
          markerId: MarkerId(busStop.name),
          position: LatLng(busStop.position[0], busStop.position[1]),
          infoWindow: InfoWindow(title: busStop.name),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.busLine.longName)),
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: LatLng(
            (widget.busLine.bounds[0] + widget.busLine.bounds[2]) / 2,
            (widget.busLine.bounds[1] + widget.busLine.bounds[3]) / 2,
          ),
          zoom: 14.0,
        ),
        markers: _markers,
        myLocationEnabled: true,
      ),
    );
  }
}



