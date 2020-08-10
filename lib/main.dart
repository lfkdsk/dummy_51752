import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';


typedef Converter<I, O> = O Function(I input);
typedef Subscriber<I, O> = SubscriberConfiguration Function(I input, O oldValue, StateSetter<O> notifier);

@immutable
class SubscriberConfiguration {
  SubscriberConfiguration(this.subscriber, this.unsubscriber);
  final VoidCallback subscriber;
  final VoidCallback unsubscriber;
}

@immutable
class Property<I, O> {
  Property();

  O convert(PropertyManager manager, I input, Converter<I, O> converter) {
    return manager.getConverterState<I, O>(this).convert(input, convertor);
  }
  
  O subscribe(PropertyManager manager, I input, Subscriber<I, O> converter) {
    return manager.getSubscriberState<I, O>(this).subscribe(input, subscriber);
  }
}

abstract class PropertyState<I, O> {
  PropertyState();

  void dispose() { }
}

class ConverterPropertyState<I, O> extends PropertyState<I, O> {
  ConverterPropertyState();

  I _lastInput;
  O _output;

  O convert(PropertyManager manager, I input, Converter<I, O> converter) {
    assert(input != null);
    if (input != _lastInput) {
      _lastInput = input;
      _output = converter(input);
    }
    return _output;
  }
}

class PropertyState<I, O> {
  SubscriberPropertyState(this.manager);

  final PropertyManager manager;

  I _lastInput;
  O _output;
  SubscriberConfiguration _configuration;

  O subscribe(PropertyManager manager, I input, Subscriber<I, O> converter) {
    if (input != _lastInput) {
      _configuration?.unsubscriber();
      _configuration = converter(input, _output, _setter);
      _configuration?.subscriber();
      _lastInput = input;
    }
    return _output;
  }

  void _setter(O output) {
    manager.setState(() {
      _output = output;
    });
  }

  @override
  void dispose() {
    _configuration?.unsubscriber();    
  }
}

mixin PropertyManager on State<StatefulWidget> {
  final Map<Property<Object, Object>, PropertyState<Object, Object>> _states = <Property<Object, Object>, PropertyState<Object, Object>>{};

  ConverterPropertyState<I, O> getConverterState<I, O>(Property<I, O> property) {
    return _states.putIfAbsent(property, () => ConverterPropertyState<I, O>(this)) as ConverterPropertyState<I, O>;
  }

  SubscriberPropertyState<I, O> getSubscriberState<I, O>(Property<I, O> property) {
    return _states.putIfAbsent(property, () => SubscriberPropertyState<I, O>(this)) as SubscriberPropertyState<I, O>;
  }

  @override
  void dispose() {
    for (PropertyState<Object, Object>> state in _states)
      state.dispose();
    super.dispose();
  }
}

abstract class PropertyWidget extends StatefulWidget {
  PropertyWidget({ Key key }) : super(key: key);

  Widget build(BuildContext context, PropertyManager propertyManager);

  State<PropertyWidget> createState() => _PropertyWidgetState();
}

class _PropertyWidgetState extends State<PropertyWidget> with PropertyManager {
  Widget build(BuildContext context) => widget.build(context, this);
}



void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Example(userId: 1),
    );
  }
}

class User {
  User(this.name);
  final String name;
}

Future<User> fetchUser(int userId) async {
  await Future.delayed(const Duration(seconds: 2));
  return User('user$userId');
}

SubscriberConfiguration futureSubscriber<T>(Future<T> input, AsyncSnapshot<T> oldValue, StateSetter<AsyncSnapshot<T>> notifier) {
  bool _active = false;
  return SubscriberConfiguration(
    () {
      _active = true;
      notifier(oldValue.inState(ConnectionState.waiting));
      input.then(
        (T value) {
          if (_active)
            notifier(AsyncSnapshot.withData(ConnectionState.done, value);
        },
        onError: (Object error, StackTrace trace) {
          if (_active)
            notifier(AsyncSnapshot.withError(ConnectionState.done, error, trace));
        },
      );
    },
    () {
      _active = false; // no way to cancel a future, sadly
    },
  );
}

SubscriberConfiguration valueListenableSubscriber<T>(ValueListenable<T> input, T oldValue, StateSetter<T> notifier) {
  return SubscriberConfiguration(
    () => input.addListener(notifier),
    () => input.removeListener(notifier),
  );
}

class Example extends StatefulWidget {
  Example({ Key key, this.userId }): super(key: key);

  final int userId;

  @override
  _ExampleState createState() => _ExampleState();
}

class _ExampleState extends State<Example> with PropertyManager {
  Property userFuture = Property();
  Property userSnapshot = Property();

  @override
  Widget build(BuildContext context) {
    var future = userFuture.convert(this, widget.userId, fetchUser);
    var snapshot = userSnapshot.subscribe(this, future, futureSubscriber);
    if (!snapshot.hasData)
      return Text('loading');
    return Text(snapshot.data.name);
  }
}


class Example2 extends PropertyWidget {
  Example2({ Key key, this.userId }): super(key: key);

  final int userId;

  static Property userFuture = Property();
  static Property userSnapshot = Property();

  @override
  Widget build(BuildContext context, PropertyManager manager) {
    var future = userFuture.convert(manager, userId, fetchUser);
    var snapshot = userSnapshot.subscribe(manager, future, futureSubscriber);
    if (!snapshot.hasData)
      return Text('loading');
    return Text(snapshot.data.name);
  }
}
