import 'package:mood_app/api/api.dart';
import 'package:mood_app/loginmodel.dart';
import 'package:mood_app/modeltest2.dart';

/// Endpoints for https://dummyjson.com
class ObjectService {
  ObjectService({ApiClient? client}) : _client = client ?? ApiManager.client;

  final ApiClient _client;

  /// GET /products?limit=&skip=
  ///
  /// The response is an object with `products`, `total`, `skip` and `limit`.
  /// Use [limit] and [skip] for paging (`limit: 0` returns all products).
  Future<ModelTest2> getProducts({int? limit, int? skip}) {
    return _client.get(
      '/products',
      query: {'limit': limit, 'skip': skip},
      parser: (json) => ModelTest2.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<LoginModel> login({required String username, required String password})async {
    return _client.post(
      '/user/login',
      headers: { 'Content-Type': 'application/json' },
      
      body: {
        'username': username,
        'password': password,
        'expiresInMins': 50
      },
      parser: (json) => LoginModel.fromJson(json as Map<String, dynamic>),
    );
  }

}
