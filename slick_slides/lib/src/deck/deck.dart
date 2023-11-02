import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:slick_slides/slick_slides.dart';
import 'package:slick_slides/src/deck/deck_controls.dart';
import 'package:slick_slides/src/deck/slide_config.dart';
import 'package:syntax_highlight/syntax_highlight.dart';

typedef SubSlideWidgetBuilder = Widget Function(
  BuildContext context,
  int index,
);

class SlickSlides {
  static final highlighters = <String, Highlighter>{};

  Future<void> initialize() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Highlighter.initialize(['dart', 'yaml']);
    var theme = await HighlighterTheme.loadDarkTheme();

    highlighters['dart'] = Highlighter(
      language: 'dart',
      theme: theme,
    );

    highlighters['yaml'] = Highlighter(
      language: 'yaml',
      theme: theme,
    );
  }
}

class Slide {
  const Slide({
    required WidgetBuilder builder,
    this.notes,
    this.transition,
    this.theme,
    this.onPrecache,
  })  : _builder = builder,
        _subSlideBuilder = null,
        subSlideCount = 1,
        hasSubSlides = false;

  const Slide.withSubSlides({
    required SubSlideWidgetBuilder builder,
    required this.subSlideCount,
    this.notes,
    this.transition,
    this.theme,
    this.onPrecache,
  })  : _subSlideBuilder = builder,
        _builder = null,
        hasSubSlides = true;

  final WidgetBuilder? _builder;
  final SubSlideWidgetBuilder? _subSlideBuilder;
  final String? notes;
  final SlickTransition? transition;
  final SlideThemeData? theme;
  final void Function(BuildContext context)? onPrecache;
  final int subSlideCount;
  final bool hasSubSlides;
}

class SlideDeck extends StatefulWidget {
  const SlideDeck({
    required this.slides,
    this.theme = const SlideThemeData.dark(),
    this.size = const Size(1920, 1080),
    super.key,
  });

  final List<Slide> slides;
  final SlideThemeData theme;
  final Size size;

  @override
  State<SlideDeck> createState() => SlideDeckState();
}

class _SlideIndex {
  const _SlideIndex(this.index, this.subIndex);

  _SlideIndex.fromString(String value)
      : index = int.parse(value.split(':')[0]),
        subIndex = int.parse(value.split(':')[1]);

  const _SlideIndex.first()
      : index = 0,
        subIndex = 0;

  final int index;
  final int subIndex;

  _SlideIndex next({
    required List<Slide> slides,
  }) {
    var subSlideCount = slides[index].subSlideCount;

    if (subIndex + 1 < subSlideCount) {
      return _SlideIndex(index, subIndex + 1);
    } else if (index + 1 < slides.length) {
      return _SlideIndex(index + 1, 0);
    } else {
      return this;
    }
  }

  _SlideIndex prev({
    required List<Slide> slides,
  }) {
    if (index > 0) {
      return _SlideIndex(index - 1, slides[index - 1].subSlideCount - 1);
    } else {
      return this;
    }
  }

  @override
  String toString() {
    return '$index:$subIndex';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SlideIndex &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          subIndex == other.subIndex;

  @override
  int get hashCode => index.hashCode ^ subIndex.hashCode * 5179;
}

class _SlideArguments {
  const _SlideArguments({
    required this.animateContents,
    required this.animateTransition,
  });

  final bool animateContents;
  final bool animateTransition;
}

class SlideDeckState extends State<SlideDeck> {
  _SlideIndex _index = const _SlideIndex(0, 0);

  final _navigatorKey = GlobalKey<NavigatorState>();

  final _focusNode = FocusNode();
  Timer? _controlsTimer;
  bool _mouseMovedRecently = false;
  bool _mouseInsideControls = false;

  final _heroController = MaterialApp.createMaterialHeroController();

  @override
  void initState() {
    super.initState();
    _focusNode.requestFocus();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _precacheSlide(1);
    });
  }

  void _precacheSlide(int index) {
    if (index >= widget.slides.length || index < 0) {
      return;
    }
    var slide = widget.slides[index];
    slide.onPrecache?.call(context);
  }

  @override
  void dispose() {
    super.dispose();
    _focusNode.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();

    SchedulerBinding.instance.addPostFrameCallback((timeStamp) {
      _navigatorKey.currentState?.pushReplacement(
        _generateRoute(RouteSettings(name: '$_index')),
      );
    });
  }

  void _onChangeSlide(_SlideIndex newIndex, _SlideArguments arguments) {
    if (_index != newIndex) {
      // Precache the next and previous slides.
      _precacheSlide(newIndex.index - 1);
      _precacheSlide(newIndex.index + 1);

      setState(() {
        _index = newIndex;
        _navigatorKey.currentState?.pushReplacementNamed(
          '$_index',
          arguments: arguments,
        );
      });
      _index = newIndex;
    }
  }

  void _onNext() {
    var nextIndex = _index.next(
      slides: widget.slides,
    );

    _onChangeSlide(
      nextIndex,
      _SlideArguments(
        animateContents: true,
        animateTransition: _index.index != nextIndex.index,
      ),
    );
  }

  void _onPrevious() {
    _onChangeSlide(
      _index.prev(
        slides: widget.slides,
      ),
      const _SlideArguments(
        animateContents: false,
        animateTransition: false,
      ),
    );
  }

  void _onMouseMoved() {
    if (_controlsTimer != null) {
      _controlsTimer!.cancel();
    }
    _controlsTimer = Timer(
      const Duration(seconds: 2),
      () {
        if (!mounted) {
          return;
        }
        setState(() {
          _mouseMovedRecently = false;
        });
      },
    );
    if (!_mouseMovedRecently) {
      setState(() {
        _mouseMovedRecently = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_index.index >= widget.slides.length) {
      _index = _SlideIndex(widget.slides.length - 1, 1);
    }

    return Focus(
      focusNode: _focusNode,
      onKey: (node, event) {
        if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowRight) {
          _onNext();
        } else if (event is RawKeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _onPrevious();
        }
        return KeyEventResult.handled;
      },
      child: MouseRegion(
        onEnter: (event) => _onMouseMoved(),
        onHover: (event) => _onMouseMoved(),
        child: Container(
          color: Colors.black,
          child: Center(
            child: AspectRatio(
              aspectRatio: widget.size.aspectRatio,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FittedBox(
                    fit: BoxFit.contain,
                    child: SizedBox(
                      width: widget.size.width,
                      height: widget.size.height,
                      child: SlideTheme(
                        data: widget.theme,
                        child: HeroControllerScope(
                          controller: _heroController,
                          child: Navigator(
                            key: _navigatorKey,
                            initialRoute: '${const _SlideIndex.first()}',
                            onGenerateRoute: _generateRoute,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16.0,
                    right: 16.0,
                    child: MouseRegion(
                      onEnter: (event) {
                        setState(() {
                          _mouseInsideControls = true;
                        });
                      },
                      onExit: (event) {
                        setState(() {
                          _mouseInsideControls = false;
                        });
                      },
                      child: DeckControls(
                        visible: _mouseMovedRecently || _mouseInsideControls,
                        onPrevious: _onPrevious,
                        onNext: _onNext,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Route _generateRoute(RouteSettings settings) {
    var index = _SlideIndex.fromString(
      settings.name ?? '${const _SlideIndex.first()}',
    );
    var slide = widget.slides[index.index];
    var transition = slide.transition;
    var arguments = settings.arguments as _SlideArguments? ??
        const _SlideArguments(animateContents: false, animateTransition: false);

    if (transition == null || !arguments.animateTransition) {
      return PageRouteBuilder(
          transitionDuration: Duration.zero,
          pageBuilder: (context, _, __) {
            var slideWidget = slide.hasSubSlides
                ? slide._subSlideBuilder!(context, index.subIndex)
                : slide._builder!(context);
            if (slide.theme != null) {
              slideWidget = SlideTheme(
                data: slide.theme!,
                child: slideWidget,
              );
            }

            return SlideConfig(
              data: SlideConfigData(
                animateIn: arguments.animateContents,
              ),
              child: slideWidget,
            );
          });
    } else {
      return transition.buildPageRoute((context) {
        var slideWidget = slide.hasSubSlides
            ? slide._subSlideBuilder!(context, index.subIndex)
            : slide._builder!(context);
        if (slide.theme != null) {
          slideWidget = SlideTheme(
            data: slide.theme!,
            child: slideWidget,
          );
        }
        return slideWidget;
      });
    }
  }
}