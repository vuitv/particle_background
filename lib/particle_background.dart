import 'dart:math';
import 'dart:core';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math.dart' as vm;

class ParticleBackground extends StatefulWidget {
  const ParticleBackground({
    this.density = 5,
    this.minSpeed = 5,
    this.maxSpeed = 10,
    this.dotSize = 2.0,
    this.dotColor = const Color(0xffFFC3D7),
    this.lineColor = const Color(0xffFFC3D7),
    this.threshold = 25,
    this.sideStrength = 10,
    this.maxLineLength = 60,
    this.lineWidth = .5,
  });

  final int density;
  final double minSpeed;
  final double maxSpeed;
  final double dotSize;
  final Color dotColor;
  final Color lineColor;
  final double threshold;
  final double sideStrength;
  final double maxLineLength;
  final double lineWidth;

  @override
  _ParticleBackgroundState createState() => _ParticleBackgroundState();
}

class _ParticleBackgroundState extends State<ParticleBackground> with TickerProviderStateMixin {
  List<Dot> dots = <Dot>[];
  double timeStep = 0.01;
  Animation? animation;
  late AnimationController controller;

  @override
  void initState() {
    super.initState();
    controller = AnimationController(vsync: this, duration: Duration(seconds: 1));

    animation = Tween(begin: 0, end: 1).animate(controller)
      ..addListener(() {
        setState(() {
          step();
        });
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          controller.repeat();
        }
      });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      calDot();
      controller.forward();
    });
  }

  void calDot() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    var numberOfDots = (.00001 * size.width * size.height).round() * widget.density;
    for (var i = 0; i < numberOfDots; i++) {
      dots.add(
        Dot.generateSimilarDot(
          color: widget.dotColor,
          size: widget.dotSize,
          minSpeed: widget.minSpeed,
          maxSpeed: widget.maxSpeed,
          rangeOfMotion: size,
        ),
      );
    }
  }

  void step() {
    if (!mounted) return;
    final size = MediaQuery.sizeOf(context);
    dots.forEach(
      (dot) => dot.stepConstrained(
        timeStep,
        size,
        widget.threshold,
        widget.sideStrength,
      ),
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: DotFieldPainter(widget, dots),
      child: const SizedBox.expand(),
    );
  }
}

class Dot extends DotPhys {
  final Color color;
  final double size;

  Dot({
    required this.color,
    required this.size,
    required Offset initialPosition,
    required double initialSpeed,
    required Offset direction,
    required double maxSpeed,
  }) : super(
          Utils.toVector(initialPosition),
          Utils.toVector(direction).normalized().scaled(initialSpeed),
          maxSpeed,
        );

  /*
  Generates a dot similar to the given values deviating by sigma
  */
  static Dot generateSimilarDot({
    required Color color,
    required double size,
    required double minSpeed,
    required double maxSpeed,
    required Size rangeOfMotion,
  }) {
    var random = Random();

    // Generate random initial direction
    var dx = random.nextBool() ? -random.nextDouble() : random.nextDouble();
    var dy = random.nextBool() ? -random.nextDouble() : random.nextDouble();
    var direction = Offset(dx, dy);

    // Random speed
    var speed = minSpeed + (maxSpeed - minSpeed) * random.nextDouble();

    var generatedDot = Dot(
      color: color,
      size: size,
      initialSpeed: speed,
      initialPosition: Offset.zero,
      direction: direction,
      maxSpeed: maxSpeed,
    );
    // Give random position within rangeOfMotion
    generatedDot._placeIn(rangeOfMotion);

    return generatedDot;
  }

  /*
  Places a dot in a random place somewhere in the given size
  */
  void _placeIn(Size size) {
    var random = Random();

    position.x = random.nextDouble() * size.width;
    position.y = random.nextDouble() * size.height;
  }
}

class DotPhys {
  vm.Vector2 position;
  vm.Vector2 speed;
  double maxSpeed;

  DotPhys(
    this.position,
    this.speed,
    this.maxSpeed,
  );

  /*
  Iterate simulation by one timeStep of stepSize, without any external forces acting upon the object
  */
  void step(double stepSize) {
    if (speed.length > maxSpeed) {
      speed.normalize();
      speed.scale(maxSpeed);
    }
    position += speed * stepSize;
  }

  /*
  Iterate simulation by one timeStep of stepSize, with given force
  */
  void stepForce(double stepSize, vm.Vector2 force) {
    force.scale(2); // Acceleration, we assume a mass of 1
    force.scale(stepSize); // Speed
    speed += force;
    step(stepSize);
  }

  /*
  Iterate simulation by one timeStep of stepSize while keeping within the bounds.
  It applies a force inversely proportional to the distance to any of the sides of the bounds.
  This can be offset with threshold, and the force increased with strenght.
  To prevent accidental NaN, a minimum is taken
  => strength * 1/min(.1, x-threshold)
  */
  void stepConstrained(double stepSize, Size bounds, double threshold, double strength) {
    var up = vm.Vector2(0, -1);
    up.scale(1 / (max(0.1, bounds.height - (position.y + threshold))));
    var down = vm.Vector2(0, 1);
    down.scale(1 / (max(0.1, position.y - threshold)));
    var left = vm.Vector2(-1, 0);
    left.scale(1 / (max(0.1, bounds.width - (position.x + threshold))));
    var right = vm.Vector2(1, 0);
    right.scale(1 / (max(0.1, position.x - threshold)));

    var force = up + down + left + right;
    force.scale(strength);
    stepForce(stepSize, force);
  }
}

class DotFieldPainter extends CustomPainter {
  DotFieldPainter(this.dotField, this.dots);

  ParticleBackground dotField;
  final List<Dot> dots;

  @override
  void paint(Canvas canvas, Size size) {
    if (dots.isEmpty) return;

    if (dotField.maxLineLength == 0) {
      paintWithoutLines(canvas);
    } else {
      paintWithLines(canvas);
    }
  }

  void paintWithLines(Canvas canvas) {
    var dotPaint = Paint();
    dotPaint.color = dotField.dotColor;
    dotPaint.style = PaintingStyle.fill;

    var linePaint = Paint();
    linePaint.color = dotField.lineColor;
    linePaint.strokeWidth = dotField.lineWidth;

    dots.forEach((dot) {
      var position = Utils.toOffset(dot.position);

      dots.forEach((neighbour) {
        if (dot == neighbour) {
          return;
        }

        if (dot.position.distanceTo(neighbour.position) < dotField.maxLineLength) {
          canvas.drawLine(Utils.toOffset(dot.position), Utils.toOffset(neighbour.position), linePaint);
        }
      });

      canvas.drawCircle(position, dot.size, dotPaint);
    });
  }

  void paintWithoutLines(Canvas canvas) {
    var paint = Paint();
    paint.color = dotField.dotColor;
    paint.style = PaintingStyle.fill;

    dots.forEach((dot) {
      var position = Utils.toOffset(dot.position);

      canvas.drawCircle(position, dot.size, paint);
    });
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return true;
  }
}

class Utils {
  static vm.Vector2 toVector(Offset offset) {
    return vm.Vector2(offset.dx, offset.dy);
  }

  static Offset toOffset(vm.Vector2 vector) {
    return Offset(vector.x, vector.y);
  }
}
