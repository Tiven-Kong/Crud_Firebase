import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import 'async_value.dart';

// REPOS
abstract class BookRepository {
  Future<Book> addBook(
      {required String author_name, required String title, required int year});
  Future<List<Book>> getBooks();
  Future<void> deleteBook(String bookId);
}

class FirebaseBooksRepository extends BookRepository {
  static const String baseUrl =
      'https://firbasestart-d97e4-default-rtdb.asia-southeast1.firebasedatabase.app';
  static const String bookCollection = "books";
  static const String allBooksUrl = '$baseUrl/$bookCollection.json';

  @override
  Future<Book> addBook(
      {required String author_name, required String title, required int year}) async {
    Uri uri = Uri.parse(allBooksUrl);

    // Create new data
    final newBookData = {'author': author_name, 'title': title, 'year': year};
    final http.Response response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: json.encode(newBookData),
    );

    // Handle errors
    if (response.statusCode != HttpStatus.ok) {
      throw Exception('Failed to add book');
    }

    // Firebase returns the new ID in 'name'
    final newId = json.decode(response.body)['name'];

    // Return created book
    return Book(id: newId, author_name: author_name, title: title, year: year);
  }

  @override
  Future<List<Book>> getBooks() async {
    Uri uri = Uri.parse(allBooksUrl);
    final http.Response response = await http.get(uri);

    // Handle errors
    if (response.statusCode != HttpStatus.ok &&
        response.statusCode != HttpStatus.created) {
      throw Exception('Failed to load');
    }

    // Return all books
    final data = json.decode(response.body) as Map<String, dynamic>?;

    if (data == null) return [];
    return data.entries
        .map((entry) => BookDto.fromJson(entry.key, entry.value))
        .toList();
  }

  @override
  Future<void> deleteBook(String bookId) async {
    try {
      Uri uri = Uri.parse('$baseUrl/$bookCollection/$bookId.json');
      final http.Response response = await http.delete(uri);
      if (response.statusCode == 200) {
        print("DeleteSuccess");
        getBooks();
      }
      if (response.statusCode != HttpStatus.ok) {
        throw Exception('Failed to delete book');
      }
    } catch (e) {
      throw Exception(e);
    }
  }
}

class MockBookRepository extends BookRepository {
  final List<Book> books = [];

  @override
  Future<Book> addBook(
      {required String author_name, required String title, required int year}) {
    return Future.delayed(Duration(seconds: 1), () {
      Book newBook = Book(
          id: "0", author_name: author_name, title: title, year: year);
      books.add(newBook);
      return newBook;
    });
  }

  @override
  Future<List<Book>> getBooks() {
    return Future.delayed(Duration(seconds: 1), () => books);
  }

  @override
  Future<void> deleteBook(String bookId) {
    books.removeWhere((book) => book.id == bookId);
    return Future.value();
  }
}

// MODEL & DTO
class BookDto {
  static Book fromJson(String id, Map<String, dynamic> json) {
    return Book(
        id: id,
        author_name: json['author'],
        title: json['title'],
        year: json['year']);
  }

  static Map<String, dynamic> toJson(Book book) {
    return {
      'author': book.author_name,
      'title': book.title,
      'year': book.year
    };
  }
}

// MODEL
class Book {
  final String id;
  final String author_name;
  final String title;
  final int year;

  Book(
      {required this.id,
        required this.author_name,
        required this.title,
        required this.year});

  @override
  bool operator ==(Object other) {
    return other is Book && other.id == id;
  }

  @override
  int get hashCode => super.hashCode ^ id.hashCode;
}




// PROVIDER
class BookProvider extends ChangeNotifier {
  final BookRepository _repository;
  AsyncValue<List<Book>>? booksState;

  BookProvider(this._repository) {
    fetchBooks();
  }

  bool get isLoading =>
      booksState != null && booksState!.state == AsyncValueState.loading;

  bool get hasData =>
      booksState != null && booksState!.state == AsyncValueState.success;

  void fetchBooks() async {
    try {
      // 1- loading state
      booksState = AsyncValue.loading();
      notifyListeners();

      // 2 - Fetch books
      booksState = AsyncValue.success(await _repository.getBooks());

      print("FetchData");

      // 3 - Handle errors
    } catch (error) {
      print("ERROR: $error");
      booksState = AsyncValue.error(error);
    }

    notifyListeners();
  }

  void addBook(String author_name, String title, int year) async {
    // 1- Call repo to add
    await _repository.addBook(
        author_name: author_name, title: title, year: year);
   print("Add SUCCESS");
    // 2- Call repo to fetch
    fetchBooks();
  }

  void deleteBook(String bookId) async {

    await _repository.deleteBook(bookId);

    // 2- Call repo to fetch
    fetchBooks();
  }
}




class App extends StatelessWidget {
  const App({super.key});

  void _onAddPressed(BuildContext context) {
    final BookProvider bookProvider = context.read<BookProvider>();
    bookProvider.addBook("New Author", "New Title", 2025);
  }

  @override
  Widget build(BuildContext context) {
    final bookProvider = Provider.of<BookProvider>(context);

    Widget content = Text('');
    if (bookProvider.isLoading) {
      content = CircularProgressIndicator();
    } else if (bookProvider.hasData) {
      List<Book> books = bookProvider.booksState!.data!;

      if (books.isEmpty) {
        content = Text("No data yet");
      } else {
        content = ListView.builder(
          itemCount: books.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(books[index].title),
            subtitle: Row(
              children: [
                Text("${books[index].author_name}"),
                Text("${books[index].year}"),
              ],
            ),
            trailing: IconButton(
              icon: Icon(Icons.delete, color: Colors.red),
              onPressed: () {
                final book = books[index];
                final BookProvider bookProvider = context.read<BookProvider>();
                bookProvider.deleteBook(book.id);
              },
            ),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
              onPressed: () => _onAddPressed(context),
              icon: const Icon(Icons.add))
        ],
      ),
      body: Center(child: content),
    );
  }
}

// 5 - MAIN
void main() async {
  // 1 - Create repository
  final BookRepository bookRepository = FirebaseBooksRepository();

  // 2-  Run app
  runApp(
    ChangeNotifierProvider(
      create: (context) => BookProvider(bookRepository),
      child: MaterialApp(debugShowCheckedModeBanner: false, home: const App()),
    ),
  );
}
