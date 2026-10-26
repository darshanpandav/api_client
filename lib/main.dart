import 'package:flutter/material.dart';
import 'package:mood_app/api/api.dart';
import 'package:mood_app/modeltest2.dart';
import 'package:mood_app/services/object_service.dart';

void main() {
  ApiManager.init(
    const ApiConfig(baseUrl: 'https://dummyjson.com'),
    type: ApiClientType.dio, // or ApiClientType.http
  );
  runApp( 
    MyApp()
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Products> items = [];
  bool isLoading = false;
  String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          
        ],
      )
    );
  }

  Future<void> login() async{
    setState(() {
      isLoading = true;
      error = null;
    });
    try{
      final result = await ObjectService().login(username: 'emilys', password: "emilyspass");
      if(result.id != null){
        print("Login Done");
        print("${result.accessToken}");
        ApiManager.setAuthToken(result.accessToken);
      }
    }on ApiException catch (e){
      setState(() => error = e.message);
    } finally{
      setState(() => isLoading = false);
    }
  }
}
