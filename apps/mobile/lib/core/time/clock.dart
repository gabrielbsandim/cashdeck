abstract interface class Clock {
  DateTime now();
}

final class SystemClock implements Clock {
  const new();

  @override
  DateTime now() => DateTime.now();
}

final class FixedClock implements Clock {
  new(this.current);

  DateTime current;

  @override
  DateTime now() => current;
}
