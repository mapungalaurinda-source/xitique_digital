// Lembretes no telemovel (notificacoes locais, so Android)
// Os fusos horarios so sao carregados quando e preciso agendar

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class Lembretes {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _pronto = false;
  static bool _fusoPronto = false;

  // Aspeto das notificacoes
  static const NotificationDetails _detalhes = NotificationDetails(
    android: AndroidNotificationDetails(
      'xitique_lembretes',
      'Lembretes do xitique',
      channelDescription: 'Avisos antes de cada ronda',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  // Prepara so o plugin (leve)
  static Future<void> iniciar() async {
    if (_pronto) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(const InitializationSettings(android: android));
    _pronto = true;
  }

  // Prepara o fuso horario de Mocambique (pesado, so quando se agenda)
  static void _iniciarFuso() {
    if (_fusoPronto) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Africa/Maputo'));
    _fusoPronto = true;
  }

  // Pede ao utilizador permissao para mostrar notificacoes
  static Future<bool> pedirPermissao() async {
    await iniciar();
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final ok = await impl?.requestNotificationsPermission();
    return ok ?? false;
  }

  // Apaga todos os lembretes agendados
  static Future<void> cancelarTodos() async {
    await iniciar();
    await _plugin.cancelAll();
  }

  // Agenda um lembrete para uma data e hora (hora de Mocambique)
  static Future<void> agendar({
    required int id,
    required DateTime quando,
    required String titulo,
    required String corpo,
  }) async {
    await iniciar();
    _iniciarFuso();
    final data = tz.TZDateTime(
        tz.local, quando.year, quando.month, quando.day, quando.hour,
        quando.minute);
    // Nao agenda datas que ja passaram
    if (data.isBefore(tz.TZDateTime.now(tz.local))) return;
    await _plugin.zonedSchedule(
      id,
      titulo,
      corpo,
      data,
      _detalhes,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  // Mostra uma notificacao agora (para testar)
  static Future<void> testar() async {
    await iniciar();
    await _plugin.show(
      0,
      'Xitique Digital',
      'Os lembretes estao a funcionar.',
      _detalhes,
    );
  }
}