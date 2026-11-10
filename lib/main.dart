// Xitique Digital - Versao final Android
// Temas, roleta, validacao de mensagens, perfil, cobranca,
// copia de seguranca, lembretes e relatorio

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Usamos "as p" para evitar conflito com o "context" do Flutter
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';
import 'lembretes.dart';

// Tema (guardado na base de dados)
final ValueNotifier<String> temaN = ValueNotifier<String>('sistema');
final ValueNotifier<int> corN = ValueNotifier<int>(0);

const List<Color> coresApp = [
  Colors.green,
  Colors.blue,
  Colors.purple,
  Colors.orange,
  Colors.teal,
  Colors.red,
];

// So mostramos cobranca e lembretes no Android
bool get ehAndroid => defaultTargetPlatform == TargetPlatform.android;

// Funcao principal: e aqui que a app comeca
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Le o tema guardado (se falhar usa o automatico)
  try {
    temaN.value = (await Db.lerConfig('tema')) ?? 'sistema';
    final c = int.tryParse((await Db.lerConfig('cor')) ?? '') ?? 0;
    corN.value = (c >= 0 && c < coresApp.length) ? c : 0;
  } catch (_) {}
  runApp(const XitiqueApp());
}

// Constroi um tema a partir da cor e do brilho
ThemeData construirTema(Color cor, Brightness b, {bool preto = false}) {
  var esq = ColorScheme.fromSeed(seedColor: cor, brightness: b);
  if (preto) {
    // Tema preto: fundo totalmente preto (poupa bateria em ecras AMOLED)
    esq = esq.copyWith(
      surface: Colors.black,
      surfaceContainerLow: const Color(0xFF121212),
      surfaceContainer: const Color(0xFF1A1A1A),
      surfaceContainerHigh: const Color(0xFF202020),
    );
  }
  return ThemeData(
    colorScheme: esq,
    useMaterial3: true,
    scaffoldBackgroundColor: preto ? Colors.black : null,
  );
}

// Funcoes auxiliares

// Mostra 500.0 como "500" e 12.5 como "12.50"
String formatarValor(num v) {
  if (v == v.truncateToDouble()) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

// Mostra uma data como dd/mm/aaaa
String formatarData(DateTime d) {
  final dia = d.day.toString().padLeft(2, '0');
  final mes = d.month.toString().padLeft(2, '0');
  return '$dia/$mes/${d.year}';
}

// Ignora as horas de uma data (fica so o dia)
DateTime soDia(DateTime d) => DateTime(d.year, d.month, d.day);

// Texto do periodo: 0 = semanal, 1 = mensal
String textoPeriodo(int periodo) => periodo == 0 ? 'semanal' : 'mensal';

// Texto do modo de ordem: 0 = entrada, 1 = sorteio, 2 = escolha
String textoModo(int modo) {
  if (modo == 1) return 'sorteio';
  if (modo == 2) return 'cada um escolhe';
  return 'ordem de entrada';
}

// Calcula a data de uma ronda (indice comeca em 0)
DateTime dataDaRonda(Map<String, dynamic> grupo, int indice) {
  final inicio = DateTime.tryParse((grupo['data_inicio'] ?? '').toString()) ??
      DateTime.now();
  final periodo = (grupo['periodo'] ?? 1) as int;

  if (periodo == 0) {
    // Semanal: soma 7 dias por ronda
    return inicio.add(Duration(days: 7 * indice));
  }
  // Mensal: soma meses (dia limitado a 28 para evitar meses curtos)
  final dia = inicio.day > 28 ? 28 : inicio.day;
  return DateTime(inicio.year, inicio.month + indice, dia);
}

// Mostra uma mensagem curta no fundo do ecra
void aviso(BuildContext context, String texto) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
}

// Janela de confirmacao (devolve true se o utilizador confirmar)
Future<bool> confirmar(BuildContext context, String texto,
    {String botao = 'Eliminar'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirmar'),
      content: Text(texto),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(botao),
        ),
      ],
    ),
  );
  return r == true;
}

// Janela que mostra uma lista de problemas
Future<void> mostrarErros(
    BuildContext context, String titulo, List<String> erros) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(erros.map((e) => '- $e').join('\n')),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

// WhatsApp e SMS

// Fica so com os digitos de um texto
String soDigitos(String s) => s.replaceAll(RegExp(r'\D'), '');

// Converte um telefone para formato internacional (Mocambique = 258)
String telInternacional(String t) {
  var d = soDigitos(t);
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 9) d = '258$d';
  return d;
}

// Abre um link noutra aplicacao (WhatsApp, SMS...)
Future<void> abrirLink(BuildContext context, String url) async {
  try {
    final ok =
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) aviso(context, 'Nao foi possivel abrir.');
  } catch (_) {
    if (context.mounted) aviso(context, 'Nao foi possivel abrir.');
  }
}

// Pergunta se quer enviar por WhatsApp ou SMS e abre com o texto pronto
Future<void> cobrar(BuildContext context, String tel, String texto) async {
  final msg = Uri.encodeComponent(texto);
  final t = telInternacional(tel);
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.chat),
            title: const Text('WhatsApp'),
            subtitle: Text(t.isEmpty ? 'Escolher contacto' : '+$t'),
            onTap: () {
              Navigator.pop(ctx);
              abrirLink(
                  context,
                  t.isEmpty
                      ? 'https://wa.me/?text=$msg'
                      : 'https://wa.me/$t?text=$msg');
            },
          ),
          ListTile(
            leading: const Icon(Icons.sms),
            title: const Text('SMS'),
            onTap: () {
              Navigator.pop(ctx);
              abrirLink(context, 'sms:$t?body=$msg');
            },
          ),
        ],
      ),
    ),
  );
}

// Leitura e validacao de mensagens M-Pesa / e-Mola

// Resultado da leitura de uma mensagem
class ExtraidoMsg {
  final double? valor;
  final String? referencia;
  ExtraidoMsg(this.valor, this.referencia);
}

// Tenta encontrar o valor e a referencia numa mensagem copiada
ExtraidoMsg extrairMensagem(String texto) {
  double? valor;
  String? ref;

  // Procura um numero seguido de MT, MZN ou Mts
  final rv = RegExp(r'(\d+(?:[.,]\d{1,2})?)\s*(?:MT|MZN|Mts?)',
      caseSensitive: false);
  final mv = rv.firstMatch(texto);
  if (mv != null) {
    valor = double.tryParse(mv.group(1)!.replaceAll(',', '.'));
  }

  // Procura um codigo de 8 a 14 caracteres com letras E numeros
  final rr = RegExp(r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{8,14}\b');
  final mr = rr.firstMatch(texto);
  if (mr != null) ref = mr.group(0);

  return ExtraidoMsg(valor, ref);
}

// Uma referencia valida tem 8 a 14 letras/numeros, com pelo menos uma de cada
bool referenciaValida(String r) {
  return RegExp(r'^(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{8,14}$')
      .hasMatch(r);
}

// Resultado da validacao
class ResultadoMsg {
  final String? referencia;
  final List<String> erros; // impedem guardar
  final List<String> avisos; // guardam como NAO CONFIRMADO
  ResultadoMsg(this.referencia, this.erros, this.avisos);
  bool get ok => erros.isEmpty;
}

// Valida uma mensagem colada
// Atencao: as regras sao aproximadas e nao provam que a mensagem e verdadeira
ResultadoMsg validarMensagem(String texto,
    {double? valorDigitado, String numeroRecebe = ''}) {
  final erros = <String>[];
  final avisos = <String>[];
  final t = texto.trim();
  final baixo = t.toLowerCase();
  final ex = extrairMensagem(t);

  const palavras = [
    'm-pesa',
    'mpesa',
    'e-mola',
    'emola',
    'mkesh',
    'm-kesh',
    'confirmad',
    'transfer'
  ];

  if (t.length < 25) {
    erros.add('A mensagem e demasiado curta para ser uma confirmacao.');
  }
  if (!palavras.any((w) => baixo.contains(w))) {
    erros.add('Nao parece uma mensagem M-Pesa, e-Mola ou mKesh.');
  }
  if (ex.valor == null) {
    erros.add('Nao encontrei o valor na mensagem (ex: 500.00MT).');
  }
  if (ex.referencia == null) {
    erros.add('Nao encontrei a referencia da transacao.');
  }
  if (ex.valor != null &&
      valorDigitado != null &&
      (ex.valor! - valorDigitado).abs() > 0.009) {
    erros.add('O valor da mensagem (${formatarValor(ex.valor!)}) e diferente '
        'do valor digitado (${formatarValor(valorDigitado)}).');
  }

  // Se o grupo tem numero, a mensagem deve te-lo
  final num = soDigitos(numeroRecebe);
  if (num.length >= 9) {
    final fim = num.substring(num.length - 9);
    if (!soDigitos(t).contains(fim)) {
      avisos.add('A mensagem nao mostra o numero do grupo ($fim).');
    }
  }
  return ResultadoMsg(ex.referencia, erros, avisos);
}

// Calculos (multa, fundo, score, estados)
class Calc {
  final Map<String, dynamic> grupo;
  final List<Map<String, dynamic>> membros; // ja ordenados
  final List<Map<String, dynamic>> pagamentos;

  Calc(this.grupo, this.membros, this.pagamentos);

  double get valor => (grupo['valor'] as num).toDouble();
  double get multaPct => ((grupo['multa_pct'] ?? 0) as num).toDouble();
  double get fundoPct => ((grupo['fundo_pct'] ?? 0) as num).toDouble();
  int get rondas => membros.length;

  // Membro ativo = ainda nao desistiu
  bool ativo(Map<String, dynamic> m) => (m['ativo'] ?? 1) == 1;
  int get nAtivos => membros.where((m) => ativo(m)).length;

  // Pagamentos de um membro numa ronda
  List<Map<String, dynamic>> _pagsDe(int membroId, int ronda) {
    return pagamentos
        .where((x) => x['membro_id'] == membroId && x['ronda'] == ronda)
        .toList();
  }

  // Soma dos pagamentos CONFIRMADOS
  double conf(int membroId, int ronda) {
    double s = 0;
    for (final x in _pagsDe(membroId, ronda)) {
      if (x['confirmado'] == 1) s += (x['valor'] as num).toDouble();
    }
    return s;
  }

  // Soma dos pagamentos por confirmar
  double pend(int membroId, int ronda) {
    double s = 0;
    for (final x in _pagsDe(membroId, ronda)) {
      if (x['confirmado'] == 0) s += (x['valor'] as num).toDouble();
    }
    return s;
  }

  // Estado: 0 = em falta, 1 = parcial, 2 = pago
  int estado(int membroId, int ronda) {
    final c = conf(membroId, ronda);
    if (c >= valor - 0.001) return 2;
    if (c > 0) return 1;
    return 0;
  }

  // Data em que o membro completou o pagamento da ronda (ou null)
  DateTime? quitacao(int membroId, int ronda) {
    final lista = _pagsDe(membroId, ronda)
        .where((x) => x['confirmado'] == 1)
        .toList();
    lista.sort((a, b) => a['data'].toString().compareTo(b['data'].toString()));
    double acc = 0;
    for (final x in lista) {
      acc += (x['valor'] as num).toDouble();
      if (acc >= valor - 0.001) return DateTime.tryParse(x['data'].toString());
    }
    return null;
  }

  // Pontualidade: 0 = a tempo, 1 = atrasado, -1 = ainda nao se aplica
  int pontualidade(Map<String, dynamic> m, int ronda) {
    final id = m['id'] as int;
    final venc = soDia(dataDaRonda(grupo, ronda));
    final q = quitacao(id, ronda);
    if (q != null) return soDia(q).isAfter(venc) ? 1 : 0;
    if (!ativo(m)) return -1;
    return soDia(DateTime.now()).isAfter(venc) ? 1 : -1;
  }

  // Numero de rondas em atraso de um membro
  int atrasos(Map<String, dynamic> m) {
    int n = 0;
    for (var r = 0; r < rondas; r++) {
      if (pontualidade(m, r) == 1) n++;
    }
    return n;
  }

  // Multa total devida por um membro (todas as rondas atrasadas)
  double multaDe(Map<String, dynamic> m) {
    if (multaPct <= 0) return 0;
    return atrasos(m) * valor * multaPct / 100;
  }

  // Score de confianca (0 a 100) ou null se ainda nao ha historico
  double? score(Map<String, dynamic> m) {
    int aTempo = 0;
    int tarde = 0;
    for (var r = 0; r < rondas; r++) {
      final pt = pontualidade(m, r);
      if (pt == 0) aTempo++;
      if (pt == 1) tarde++;
    }
    if (aTempo + tarde == 0) return null;
    return aTempo * 100 / (aTempo + tarde);
  }

  // Total confirmado numa ronda (antes do fundo)
  double brutoRonda(int r) {
    double s = 0;
    for (final m in membros) {
      s += conf(m['id'] as int, r);
    }
    return s;
  }

  // O que quem recebe leva (depois de tirar o fundo de reserva)
  double recebidoRonda(int r) => brutoRonda(r) * (1 - fundoPct / 100);

  // Quanto devia entrar numa ronda
  double get esperadoRonda => valor * nAtivos;

  // Ronda completa = todos os ativos pagaram
  bool completa(int r) {
    final e = esperadoRonda;
    return e > 0 && brutoRonda(r) >= e - 0.001;
  }

  // Totais gerais
  double get totalConf {
    double s = 0;
    for (final x in pagamentos) {
      if (x['confirmado'] == 1) s += (x['valor'] as num).toDouble();
    }
    return s;
  }

  double get totalPend {
    double s = 0;
    for (final x in pagamentos) {
      if (x['confirmado'] == 0) s += (x['valor'] as num).toDouble();
    }
    return s;
  }

  double get fundo => totalConf * fundoPct / 100;

  double get multasTotal {
    double s = 0;
    for (final m in membros) {
      s += multaDe(m);
    }
    return s;
  }

  // Quanto um membro ja pagou (confirmado) em todas as rondas
  double pagoPor(int membroId) {
    double s = 0;
    for (final x in pagamentos) {
      if (x['membro_id'] == membroId && x['confirmado'] == 1) {
        s += (x['valor'] as num).toDouble();
      }
    }
    return s;
  }

  // Texto com o acerto de um membro que desistiu
  String acerto(int indice) {
    final m = membros[indice];
    final pago = pagoPor(m['id'] as int);
    if (completa(indice)) {
      final recebido = recebidoRonda(indice);
      final divida = recebido - pago;
      if (divida > 0) {
        return 'Ja recebeu ${formatarValor(recebido)} MZN e pagou '
            '${formatarValor(pago)}. Deve devolver ${formatarValor(divida)} MZN.';
      }
      return 'Ja recebeu a sua ronda e pagou ${formatarValor(pago)} MZN. '
          'Nada a devolver.';
    }
    return 'Ainda nao recebeu. Pagou ${formatarValor(pago)} MZN, '
        'que o grupo deve devolver.';
  }

  // Mensagem de cobranca com as rondas ja vencidas e por pagar (ou null)
  String? mensagemCobranca(Map<String, dynamic> m) {
    final hoje = soDia(DateTime.now());
    final id = m['id'] as int;
    final linhas = <String>[];
    double total = 0;
    for (var r = 0; r < rondas; r++) {
      final falta = valor - conf(id, r);
      if (falta <= 0.001) continue;
      final venc = soDia(dataDaRonda(grupo, r));
      if (venc.isAfter(hoje)) continue;
      linhas.add('- Ronda ${r + 1} (${formatarData(venc)}): '
          '${formatarValor(falta)} MZN');
      total += falta;
    }
    if (linhas.isEmpty) return null;
    return 'Ola ${m['nome']}, lembrete do xitique "${grupo['nome']}". '
        'Estao em falta:\n${linhas.join('\n')}\n'
        'Total: ${formatarValor(total)} MZN. Obrigado!';
  }

  // Resumo da ronda para copiar e colar no WhatsApp
  String resumoRonda(int r) {
    final sb = StringBuffer();
    sb.writeln('XITIQUE ${grupo['nome']}');
    sb.writeln('Ronda ${r + 1} de $rondas - '
        '${formatarData(dataDaRonda(grupo, r))}');
    sb.writeln('Recebe: ${membros[r]['nome']}');
    sb.writeln('');
    for (final m in membros) {
      if (!ativo(m)) continue;
      final id = m['id'] as int;
      final e = estado(id, r);
      String t;
      if (e == 2) {
        t = 'PAGO';
      } else if (e == 1) {
        t = 'PARCIAL (${formatarValor(conf(id, r))}/${formatarValor(valor)})';
      } else {
        t = 'EM FALTA';
      }
      sb.writeln('- ${m['nome']}: $t');
    }
    sb.writeln('');
    sb.writeln('Recolhido: ${formatarValor(brutoRonda(r))} de '
        '${formatarValor(esperadoRonda)} MZN');
    return sb.toString();
  }

  // Relatorio completo do grupo (para copiar)
  String relatorioCompleto() {
    final sb = StringBuffer();
    sb.writeln('RELATORIO DO XITIQUE ${grupo['nome']}');
    sb.writeln('Contribuicao: ${formatarValor(valor)} MZN '
        '(${textoPeriodo((grupo['periodo'] ?? 1) as int)})');
    sb.writeln('Membros: $rondas (ativos: $nAtivos)');
    sb.writeln('Multa: ${formatarValor(multaPct)}% | '
        'Fundo: ${formatarValor(fundoPct)}%');
    sb.writeln('Recolhido: ${formatarValor(totalConf)} MZN | '
        'Fundo: ${formatarValor(fundo)} MZN | '
        'Multas devidas: ${formatarValor(multasTotal)} MZN');
    sb.writeln('');
    sb.writeln('Calendario:');
    for (var i = 0; i < rondas; i++) {
      final pct = esperadoRonda > 0
          ? (brutoRonda(i) / esperadoRonda * 100).clamp(0.0, 100.0).round()
          : 0;
      sb.writeln('${i + 1}. ${membros[i]['nome']} - '
          '${formatarData(dataDaRonda(grupo, i))} - '
          '${completa(i) ? 'COMPLETA' : '$pct%'}');
    }
    sb.writeln('');
    sb.writeln('Membros:');
    for (final m in membros) {
      final s = score(m);
      sb.writeln('- ${m['nome']}${ativo(m) ? '' : ' (desistiu)'}: '
          'pagou ${formatarValor(pagoPor(m['id'] as int))} MZN, '
          'atrasos ${atrasos(m)}, '
          'score ${s == null ? 'sem dados' : '${s.round()}%'}');
    }
    return sb.toString();
  }
}

// Texto do estado de um membro numa ronda
String textoEstado(Calc c, Map<String, dynamic> m, int r) {
  final id = m['id'] as int;
  final e = c.estado(id, r);
  String t;
  if (e == 2) {
    t = 'Pago';
  } else if (e == 1) {
    t = 'Parcial ${formatarValor(c.conf(id, r))}/${formatarValor(c.valor)}';
  } else {
    t = 'Em falta';
  }
  final pd = c.pend(id, r);
  if (pd > 0) t += ' | por confirmar ${formatarValor(pd)}';
  if (c.pontualidade(m, r) == 1 && c.multaPct > 0) {
    t += ' | multa ${formatarValor(c.valor * c.multaPct / 100)}';
  }
  return t;
}

// Lembretes: calcula e agenda os avisos de todas as rondas

// Um aviso por agendar
class _Aviso {
  final DateTime quando;
  final String titulo;
  final String corpo;
  _Aviso(this.quando, this.titulo, this.corpo);
}

bool _agendando = false;

// Apaga os lembretes antigos e agenda os novos (so Android)
Future<void> reagendarLembretes() async {
  if (!ehAndroid || _agendando) return;
  _agendando = true;
  try {
    final ativo = (await Db.lerConfig('lembretes')) == '1';
    await Lembretes.cancelarTodos();
    if (!ativo) return;

    final hora = int.tryParse((await Db.lerConfig('lembrete_hora')) ?? '') ?? 8;
    final grupos = await Db.listarGrupos();
    final avisos = <_Aviso>[];

    for (final g in grupos) {
      final membros = await Db.listarMembros(g['id'] as int);
      final pags = await Db.listarPagamentos(g['id'] as int);
      final c = Calc(g, membros, pags);
      for (var r = 0; r < membros.length; r++) {
        // Rondas ja completas nao precisam de aviso
        if (c.completa(r)) continue;
        final dia = soDia(dataDaRonda(g, r));
        final recebe = membros[r]['nome'];
        final valorRonda =
            formatarValor(c.esperadoRonda * (1 - c.fundoPct / 100));
        // Aviso no dia anterior
        avisos.add(_Aviso(
          DateTime(dia.year, dia.month, dia.day - 1, hora),
          'Amanha: ronda ${r + 1} - ${g['nome']}',
          '$recebe recebe $valorRonda MZN. Lembra o grupo de pagar.',
        ));
        // Aviso no proprio dia
        avisos.add(_Aviso(
          DateTime(dia.year, dia.month, dia.day, hora),
          'Hoje: ronda ${r + 1} - ${g['nome']}',
          'Vence hoje. Confere quem ainda nao pagou.',
        ));
      }
    }

    // Fica so com os futuros, os mais proximos primeiro (maximo 60)
    final agora = DateTime.now();
    avisos.removeWhere((a) => !a.quando.isAfter(agora));
    avisos.sort((a, b) => a.quando.compareTo(b.quando));
    final n = min(avisos.length, 60);
    for (var i = 0; i < n; i++) {
      await Lembretes.agendar(
        id: i + 1,
        quando: avisos[i].quando,
        titulo: avisos[i].titulo,
        corpo: avisos[i].corpo,
      );
    }
  } catch (_) {
    // Se algo falhar, a app continua a funcionar sem lembretes
  } finally {
    _agendando = false;
  }
}

// Widget raiz da app (reage a mudancas de tema)
class XitiqueApp extends StatelessWidget {
  const XitiqueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: temaN,
      builder: (_, tema, __) => ValueListenableBuilder<int>(
        valueListenable: corN,
        builder: (_, ci, __) {
          final cor = coresApp[ci];
          return MaterialApp(
            title: 'Xitique Digital',
            debugShowCheckedModeBanner: false,
            theme: construirTema(cor, Brightness.light),
            darkTheme:
                construirTema(cor, Brightness.dark, preto: tema == 'preto'),
            themeMode: tema == 'claro'
                ? ThemeMode.light
                : (tema == 'escuro' || tema == 'preto')
                    ? ThemeMode.dark
                    : ThemeMode.system,
            home: const GruposPage(),
          );
        },
      ),
    );
  }
}

// Base de dados (SQLite) - versao 5
class Db {
  static Database? _db;

  static Future<Database> abrir() async {
    if (_db != null) return _db!;

    final caminho = p.join(await getDatabasesPath(), 'xitique.db');

    _db = await openDatabase(
      caminho,
      version: 5,
      // onCreate corre quando a base de dados e criada pela primeira vez
      onCreate: (db, versao) async {
        await db.execute(
          'CREATE TABLE grupos ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'nome TEXT NOT NULL, '
          'valor REAL NOT NULL, '
          'data_inicio TEXT, '
          'periodo INTEGER DEFAULT 1, '
          'multa_pct REAL DEFAULT 0, '
          'fundo_pct REAL DEFAULT 0, '
          'modo_ordem INTEGER DEFAULT 0, '
          'numero_recebe TEXT)',
        );
        await db.execute(
          'CREATE TABLE membros ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'grupo_id INTEGER NOT NULL, '
          'nome TEXT NOT NULL, '
          'telefone TEXT, '
          'posicao INTEGER DEFAULT 0, '
          'ativo INTEGER DEFAULT 1, '
          'pedido_ronda INTEGER)',
        );
        await _criarTabelaPagamentos(db);
        await db.execute('ALTER TABLE pagamentos ADD COLUMN mensagem TEXT');
        await _criarTabelaConfig(db);
      },
      // onUpgrade corre quando existe uma versao antiga da base de dados
      onUpgrade: (db, versaoAntiga, versaoNova) async {
        if (versaoAntiga < 2) {
          await db.execute(
            'CREATE TABLE membros ('
            'id INTEGER PRIMARY KEY AUTOINCREMENT, '
            'grupo_id INTEGER NOT NULL, '
            'nome TEXT NOT NULL, '
            'telefone TEXT)',
          );
        }
        if (versaoAntiga < 3) {
          await db.execute('ALTER TABLE grupos ADD COLUMN data_inicio TEXT');
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN periodo INTEGER DEFAULT 1');
        }
        if (versaoAntiga < 4) {
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN multa_pct REAL DEFAULT 0');
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN fundo_pct REAL DEFAULT 0');
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN modo_ordem INTEGER DEFAULT 0');
          await db.execute(
              'ALTER TABLE membros ADD COLUMN posicao INTEGER DEFAULT 0');
          await db.execute(
              'ALTER TABLE membros ADD COLUMN ativo INTEGER DEFAULT 1');
          await db
              .execute('ALTER TABLE membros ADD COLUMN pedido_ronda INTEGER');
          await db.execute('UPDATE membros SET posicao = id');
          await _criarTabelaPagamentos(db);
          if (versaoAntiga >= 3) {
            await db.execute(
              'INSERT INTO pagamentos '
              '(grupo_id, membro_id, ronda, valor, data, referencia, confirmado) '
              'SELECT c.grupo_id, c.membro_id, c.ronda, g.valor, '
              "datetime('now'), '', 1 "
              'FROM contribuicoes c JOIN grupos g ON g.id = c.grupo_id',
            );
          }
        }
        if (versaoAntiga < 5) {
          // Numero do grupo, mensagem guardada e tabela de configuracao
          await db.execute('ALTER TABLE grupos ADD COLUMN numero_recebe TEXT');
          await db.execute('ALTER TABLE pagamentos ADD COLUMN mensagem TEXT');
          await _criarTabelaConfig(db);
        }
      },
    );
    return _db!;
  }

  static Future<void> _criarTabelaPagamentos(Database db) async {
    await db.execute(
      'CREATE TABLE pagamentos ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'grupo_id INTEGER NOT NULL, '
      'membro_id INTEGER NOT NULL, '
      'ronda INTEGER NOT NULL, '
      'valor REAL NOT NULL, '
      'data TEXT NOT NULL, '
      'referencia TEXT, '
      'confirmado INTEGER NOT NULL DEFAULT 0)',
    );
  }

  // Tabela simples chave/valor para guardar o tema e os lembretes
  static Future<void> _criarTabelaConfig(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS config ('
      'chave TEXT PRIMARY KEY, '
      'valor TEXT)',
    );
  }

  // Configuracao

  static Future<String?> lerConfig(String chave) async {
    final db = await abrir();
    final r = await db.query('config',
        where: 'chave = ?', whereArgs: [chave], limit: 1);
    if (r.isEmpty) return null;
    return r.first['valor'] as String?;
  }

  static Future<void> guardarConfig(String chave, String valor) async {
    final db = await abrir();
    await db.insert('config', {'chave': chave, 'valor': valor},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Copia de seguranca

  // Junta todos os dados num texto (JSON)
  static Future<String> exportar() async {
    final db = await abrir();
    final dados = {
      'app': 'xitique_digital',
      'versao': 1,
      'grupos': await db.query('grupos'),
      'membros': await db.query('membros'),
      'pagamentos': await db.query('pagamentos'),
    };
    return jsonEncode(dados);
  }

  // Apaga os dados atuais e carrega os da copia
  static Future<void> importar(String texto) async {
    final d = jsonDecode(texto);
    if (d is! Map || d['app'] != 'xitique_digital') {
      throw Exception('Copia invalida');
    }
    final db = await abrir();
    await db.transaction((txn) async {
      await txn.delete('pagamentos');
      await txn.delete('membros');
      await txn.delete('grupos');
      for (final tabela in ['grupos', 'membros', 'pagamentos']) {
        for (final linha in (d[tabela] as List)) {
          await txn.insert(tabela, Map<String, Object?>.from(linha as Map));
        }
      }
    });
  }

  // Grupos

  static Future<List<Map<String, dynamic>>> listarGrupos() async {
    final db = await abrir();
    return db.rawQuery(
      'SELECT g.*, '
      '(SELECT COUNT(*) FROM membros m WHERE m.grupo_id = g.id) '
      'AS total_membros '
      'FROM grupos g ORDER BY g.id DESC',
    );
  }

  static Future<void> criarGrupo(String nome, double valor, int periodo,
      DateTime inicio, double multa, double fundo, int modo,
      String numero) async {
    final db = await abrir();
    await db.insert('grupos', {
      'nome': nome,
      'valor': valor,
      'periodo': periodo,
      'data_inicio': inicio.toIso8601String(),
      'multa_pct': multa,
      'fundo_pct': fundo,
      'modo_ordem': modo,
      'numero_recebe': numero,
    });
  }

  static Future<void> eliminarGrupo(int id) async {
    final db = await abrir();
    await db.delete('pagamentos', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('membros', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('grupos', where: 'id = ?', whereArgs: [id]);
  }

  // Membros

  static Future<List<Map<String, dynamic>>> listarMembros(int grupoId) async {
    final db = await abrir();
    return db.query(
      'membros',
      where: 'grupo_id = ?',
      whereArgs: [grupoId],
      orderBy: 'posicao ASC, id ASC',
    );
  }

  static Future<void> criarMembro(
      int grupoId, String nome, String telefone, int? pedido) async {
    final db = await abrir();
    final r = await db.rawQuery(
      'SELECT COALESCE(MAX(posicao), 0) AS m FROM membros WHERE grupo_id = ?',
      [grupoId],
    );
    final pos = (r.first['m'] as int) + 1;
    await db.insert('membros', {
      'grupo_id': grupoId,
      'nome': nome,
      'telefone': telefone,
      'posicao': pos,
      'ativo': 1,
      'pedido_ronda': pedido,
    });
  }

  static Future<void> eliminarMembro(int id) async {
    final db = await abrir();
    await db.delete('pagamentos', where: 'membro_id = ?', whereArgs: [id]);
    await db.delete('membros', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> definirAtivo(int id, bool ativo) async {
    final db = await abrir();
    await db.update('membros', {'ativo': ativo ? 1 : 0},
        where: 'id = ?', whereArgs: [id]);
  }

  // Guarda a nova ordem de recebimento (lista de ids pela ordem)
  static Future<void> guardarOrdem(List<int> ids) async {
    final db = await abrir();
    final batch = db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update('membros', {'posicao': i + 1},
          where: 'id = ?', whereArgs: [ids[i]]);
    }
    await batch.commit(noResult: true);
  }

  // Pagamentos

  static Future<List<Map<String, dynamic>>> listarPagamentos(
      int grupoId) async {
    final db = await abrir();
    return db.query('pagamentos',
        where: 'grupo_id = ?', whereArgs: [grupoId], orderBy: 'data ASC');
  }

  static Future<List<Map<String, dynamic>>> listarPagamentosMembroRonda(
      int membroId, int ronda) async {
    final db = await abrir();
    return db.query('pagamentos',
        where: 'membro_id = ? AND ronda = ?',
        whereArgs: [membroId, ronda],
        orderBy: 'data ASC');
  }

  // Verifica se uma referencia ja foi usada (ignora um pagamento, se indicado)
  static Future<bool> referenciaExiste(String ref, {int? ignorarId}) async {
    final db = await abrir();
    final r = await db.query('pagamentos',
        where:
            ignorarId == null ? 'referencia = ?' : 'referencia = ? AND id != ?',
        whereArgs: ignorarId == null ? [ref] : [ref, ignorarId],
        limit: 1);
    return r.isNotEmpty;
  }

  static Future<void> criarPagamento(int grupoId, int membroId, int ronda,
      double valor, DateTime data, String ref, String mensagem,
      bool confirmado) async {
    final db = await abrir();
    await db.insert('pagamentos', {
      'grupo_id': grupoId,
      'membro_id': membroId,
      'ronda': ronda,
      'valor': valor,
      'data': data.toIso8601String(),
      'referencia': ref,
      'mensagem': mensagem,
      'confirmado': confirmado ? 1 : 0,
    });
  }

  // Confirma um pagamento que estava por confirmar
  static Future<void> confirmarPagamento(
      int id, String ref, String mensagem) async {
    final db = await abrir();
    await db.update('pagamentos',
        {'referencia': ref, 'mensagem': mensagem, 'confirmado': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> eliminarPagamento(int id) async {
    final db = await abrir();
    await db.delete('pagamentos', where: 'id = ?', whereArgs: [id]);
  }
}

// Ecra 1: lista de grupos
class GruposPage extends StatefulWidget {
  const GruposPage({super.key});

  @override
  State<GruposPage> createState() => _GruposPageState();
}

class _GruposPageState extends State<GruposPage> {
  List<Map<String, dynamic>> grupos = [];

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final dados = await Db.listarGrupos();
    if (!mounted) return;
    setState(() => grupos = dados);
    // Sempre que os dados mudam, atualiza os lembretes
    unawaited(reagendarLembretes());
  }

  // Mostra a janela para criar um grupo novo
  Future<void> novoGrupo() async {
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final multaCtrl = TextEditingController(text: '0');
    final fundoCtrl = TextEditingController(text: '0');
    final numCtrl = TextEditingController();
    int periodo = 1;
    int modo = 0;
    DateTime inicio = DateTime.now();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Novo grupo de xitique'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(labelText: 'Nome do grupo'),
                ),
                TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor da contribuicao (MZN)',
                  ),
                ),
                TextField(
                  controller: numCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Numero que recebe (M-Pesa/e-Mola)',
                  ),
                ),
                TextField(
                  controller: multaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Multa por atraso (%) - 0 desliga',
                  ),
                ),
                TextField(
                  controller: fundoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Fundo de reserva (%) - 0 desliga',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: periodo,
                  decoration: const InputDecoration(labelText: 'Periodo'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Mensal')),
                    DropdownMenuItem(value: 0, child: Text('Semanal')),
                  ],
                  onChanged: (v) => setDialog(() => periodo = v ?? 1),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: modo,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Ordem de recebimento'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Ordem de entrada')),
                    DropdownMenuItem(value: 1, child: Text('Sorteio (roleta)')),
                    DropdownMenuItem(
                        value: 2, child: Text('Cada um escolhe a ronda')),
                  ],
                  onChanged: (v) => setDialog(() => modo = v ?? 0),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Inicio: ${formatarData(inicio)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: inicio,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setDialog(() => inicio = d);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (guardar == true) {
      final nome = nomeCtrl.text.trim();
      final valor = double.tryParse(valorCtrl.text.trim()) ?? 0;
      final multa =
          (double.tryParse(multaCtrl.text.trim().replaceAll(',', '.')) ?? 0)
              .clamp(0.0, 100.0)
              .toDouble();
      final fundo =
          (double.tryParse(fundoCtrl.text.trim().replaceAll(',', '.')) ?? 0)
              .clamp(0.0, 100.0)
              .toDouble();

      if (nome.isNotEmpty && valor > 0) {
        await Db.criarGrupo(nome, valor, periodo, inicio, multa, fundo, modo,
            numCtrl.text.trim());
        await carregar();
      }
    }
  }

  Future<void> abrirGrupo(Map<String, dynamic> g) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GrupoPage(grupo: g)),
    );
    await carregar();
  }

  Future<void> abrirConfig() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ConfigPage()),
    );
    // Se restaurou uma copia, os grupos mudaram
    await carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Xitique Digital'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Definicoes',
            onPressed: abrirConfig,
          ),
        ],
      ),
      body: grupos.isEmpty
          ? const Center(
              child: Text(
                'Ainda nao tens grupos.\nCarrega no + para criar.',
                textAlign: TextAlign.center,
              ),
            )
          : ListView.builder(
              itemCount: grupos.length,
              itemBuilder: (context, i) {
                final g = grupos[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(g['nome']),
                    subtitle: Text(
                      '${formatarValor(g['valor'])} MZN | '
                      '${textoPeriodo((g['periodo'] ?? 1) as int)} | '
                      '${g['total_membros']} membros',
                    ),
                    onTap: () => abrirGrupo(g),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        final ok = await confirmar(context,
                            'Eliminar o grupo "${g['nome']}" e todos os dados dele?');
                        if (ok) {
                          await Db.eliminarGrupo(g['id']);
                          await carregar();
                        }
                      },
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: novoGrupo,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// Ecra de definicoes (tema, lembretes e copia de seguranca)
class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  static const Map<String, String> temas = {
    'sistema': 'Automatico',
    'claro': 'Claro',
    'escuro': 'Escuro',
    'preto': 'Preto',
  };

  bool lembretesAtivos = false;
  int horaLembrete = 8;

  @override
  void initState() {
    super.initState();
    carregarLembretes();
  }

  // Le as definicoes de lembretes guardadas
  Future<void> carregarLembretes() async {
    final a = await Db.lerConfig('lembretes');
    final h = int.tryParse((await Db.lerConfig('lembrete_hora')) ?? '') ?? 8;
    if (!mounted) return;
    setState(() {
      lembretesAtivos = a == '1';
      horaLembrete = h;
    });
  }

  // Liga ou desliga os lembretes (pede permissao ao ligar)
  Future<void> mudarLembretes(bool v) async {
    if (v) {
      final ok = await Lembretes.pedirPermissao();
      if (!mounted) return;
      if (!ok) {
        aviso(context,
            'Sem permissao para notificacoes. Ativa nas definicoes do telemovel.');
        return;
      }
    }
    await Db.guardarConfig('lembretes', v ? '1' : '0');
    if (!mounted) return;
    setState(() => lembretesAtivos = v);
    await reagendarLembretes();
  }

  // Escolhe a hora dos avisos
  Future<void> escolherHora() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: horaLembrete, minute: 0),
    );
    if (t == null) return;
    await Db.guardarConfig('lembrete_hora', '${t.hour}');
    if (!mounted) return;
    setState(() => horaLembrete = t.hour);
    await reagendarLembretes();
  }

  // Mostra uma notificacao de teste
  Future<void> testarLembrete() async {
    final ok = await Lembretes.pedirPermissao();
    if (!mounted) return;
    if (!ok) {
      aviso(context, 'Sem permissao para notificacoes.');
      return;
    }
    await Lembretes.testar();
    if (!mounted) return;
    aviso(context, 'Notificacao de teste enviada.');
  }

  // Copia todos os dados para a area de transferencia
  Future<void> copiarSeguranca() async {
    final texto = await Db.exportar();
    await Clipboard.setData(ClipboardData(text: texto));
    if (!mounted) return;
    aviso(
        context,
        'Copia guardada na area de transferencia. '
        'Cola num sitio seguro (notas, e-mail, WhatsApp para ti).');
  }

  // Restaura os dados a partir de um texto colado
  Future<void> restaurar() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar copia'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Atencao: isto APAGA os dados atuais e coloca os da copia.',
                style: TextStyle(fontSize: 12)),
            TextField(
              controller: ctrl,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Cola aqui a copia'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Db.importar(ctrl.text.trim());
      if (!mounted) return;
      aviso(context, 'Copia restaurada com sucesso.');
    } catch (_) {
      if (!mounted) return;
      aviso(context, 'Copia invalida. Os dados nao foram alterados.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Definicoes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Tema',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: temas.entries
                .map((e) => ChoiceChip(
                      label: Text(e.value),
                      selected: temaN.value == e.key,
                      onSelected: (_) async {
                        temaN.value = e.key;
                        await Db.guardarConfig('tema', e.key);
                        setState(() {});
                      },
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          const Text('Cor da app',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: List.generate(coresApp.length, (i) {
              return InkWell(
                customBorder: const CircleBorder(),
                onTap: () async {
                  corN.value = i;
                  await Db.guardarConfig('cor', '$i');
                  setState(() {});
                },
                child: CircleAvatar(
                  backgroundColor: coresApp[i],
                  child: corN.value == i
                      ? const Icon(Icons.check, color: Colors.white)
                      : null,
                ),
              );
            }),
          ),

          // Lembretes (so no Android)
          if (ehAndroid) ...[
            const SizedBox(height: 28),
            const Text('Lembretes',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Avisar antes de cada ronda'),
              subtitle: const Text(
                  'No dia anterior e no proprio dia, sem precisar de internet'),
              value: lembretesAtivos,
              onChanged: mudarLembretes,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              enabled: lembretesAtivos,
              title: const Text('Hora do aviso'),
              trailing:
                  Text('${horaLembrete.toString().padLeft(2, '0')}:00'),
              onTap: lembretesAtivos ? escolherHora : null,
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.notifications_active),
              label: const Text('Testar notificacao agora'),
              onPressed: testarLembrete,
            ),
          ],

          const SizedBox(height: 28),
          const Text('Copia de seguranca',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar todos os dados'),
            onPressed: copiarSeguranca,
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.restore),
            label: const Text('Restaurar de uma copia'),
            onPressed: restaurar,
          ),
        ],
      ),
    );
  }
}

// Roleta da sorte
// Cada giro decide quem recebe a posicao seguinte
class RoletaPainter extends CustomPainter {
  final List<String> nomes;
  final double angulo; // rotacao atual da roda (radianos)

  RoletaPainter({required this.nomes, required this.angulo});

  static const List<Color> cores = [
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00ACC1),
    Color(0xFFD81B60),
    Color(0xFF6D4C41),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = min(size.width, size.height) / 2 - 8;
    final n = nomes.length;
    if (n == 0) return;
    final a = 2 * pi / n;
    final rect = Rect.fromCircle(center: c, radius: r);

    // Roda a roda toda em volta do centro
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angulo);
    canvas.translate(-c.dx, -c.dy);

    for (var i = 0; i < n; i++) {
      final inicio = -pi / 2 + i * a;
      // Fatia colorida
      canvas.drawArc(
          rect, inicio, a, true, Paint()..color = cores[i % cores.length]);
      // Contorno branco
      canvas.drawArc(
          rect,
          inicio,
          a,
          true,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);

      // Nome escrito ao longo do raio
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(inicio + a / 2);
      final tp = TextPainter(
        text: TextSpan(
          text: nomes[i],
          style: TextStyle(
            color: Colors.white,
            fontSize: n > 8 ? 11 : 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      )..layout(maxWidth: r * 0.62);
      tp.paint(canvas, Offset(r * 0.30, -tp.height / 2));
      canvas.restore();
    }
    canvas.restore();

    // Centro da roda
    canvas.drawCircle(c, 16, Paint()..color = Colors.white);
    canvas.drawCircle(
        c,
        16,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.black54);

    // Ponteiro fixo no topo
    final seta = Path()
      ..moveTo(c.dx - 13, c.dy - r - 6)
      ..lineTo(c.dx + 13, c.dy - r - 6)
      ..lineTo(c.dx, c.dy - r + 22)
      ..close();
    canvas.drawPath(seta, Paint()..color = Colors.red);
    canvas.drawPath(
        seta,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant RoletaPainter old) => true;
}

class RoletaDialog extends StatefulWidget {
  final List<Map<String, dynamic>> membros;

  const RoletaDialog({super.key, required this.membros});

  @override
  State<RoletaDialog> createState() => _RoletaDialogState();
}

class _RoletaDialogState extends State<RoletaDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final Random rnd = Random();

  late List<Map<String, dynamic>> restantes; // ainda sem posicao
  final List<Map<String, dynamic>> ordem = []; // ja sorteados
  double angulo = 0;
  double _inicio = 0;
  double _fim = 0;
  bool girando = false;

  bool get terminou => restantes.isEmpty;

  @override
  void initState() {
    super.initState();
    restantes = List.of(widget.membros);
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 4));
    // A cada imagem calcula o angulo da roda (abranda no fim)
    _ctrl.addListener(() {
      setState(() {
        angulo = _inicio +
            (_fim - _inicio) * Curves.easeOutCubic.transform(_ctrl.value);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Gira a roda e escolhe um vencedor
  Future<void> girar() async {
    if (girando || restantes.length < 2) return;
    final n = restantes.length;
    final a = 2 * pi / n;
    final w = rnd.nextInt(n); // indice do vencedor

    // Pequena variacao para nao parar sempre no meio da fatia
    final variacao = (rnd.nextDouble() - 0.5) * a * 0.7;
    // Angulo em que o centro da fatia w fica debaixo do ponteiro
    final alvo = (-(w * a + a / 2 + variacao)) % (2 * pi);
    final atual = angulo % (2 * pi);
    var delta = alvo - atual;
    if (delta < 0) delta += 2 * pi;

    _inicio = angulo;
    _fim = angulo + delta + 2 * pi * (5 + rnd.nextInt(3)); // 5 a 7 voltas
    setState(() => girando = true);
    await _ctrl.forward(from: 0);
    if (!mounted) return;

    setState(() {
      girando = false;
      ordem.add(restantes[w]);
      restantes.removeAt(w);
      // O ultimo fica automaticamente na ultima posicao
      if (restantes.length == 1) {
        ordem.add(restantes.first);
        restantes.clear();
      }
      angulo = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(terminou ? 'Ordem sorteada!' : 'Roleta da sorte'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!terminou)
                SizedBox(
                  width: 260,
                  height: 260,
                  child: CustomPaint(
                    painter: RoletaPainter(
                      nomes:
                          restantes.map((m) => m['nome'].toString()).toList(),
                      angulo: angulo,
                    ),
                  ),
                ),
              if (!terminou)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    girando
                        ? 'A girar...'
                        : 'Quem recebe na posicao ${ordem.length + 1}? '
                            'Carrega em Girar.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ...List.generate(
                ordem.length,
                (i) => ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(ordem[i]['nome'].toString()),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: girando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        if (!terminou)
          FilledButton(
            onPressed: girando ? null : girar,
            child: const Text('Girar'),
          ),
        if (terminou)
          FilledButton(
            onPressed: () => Navigator.pop(
                context, ordem.map((m) => m['id'] as int).toList()),
            child: const Text('Aceitar'),
          ),
      ],
    );
  }
}

// Ecra 2: detalhes do grupo (4 separadores)
// Membros, pagamentos, calendario e painel
class GrupoPage extends StatefulWidget {
  final Map<String, dynamic> grupo;

  const GrupoPage({super.key, required this.grupo});

  @override
  State<GrupoPage> createState() => _GrupoPageState();
}

class _GrupoPageState extends State<GrupoPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  List<Map<String, dynamic>> membros = [];
  List<Map<String, dynamic>> pagamentos = [];
  int rondaSel = 0;
  bool _primeira = true;

  int get grupoId => widget.grupo['id'] as int;
  int get modo => (widget.grupo['modo_ordem'] ?? 0) as int;
  Calc get calc => Calc(widget.grupo, membros, pagamentos);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _tab.addListener(() => setState(() {}));
    carregar();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> carregar() async {
    final m = await Db.listarMembros(grupoId);
    final pg = await Db.listarPagamentos(grupoId);
    if (!mounted) return;
    setState(() {
      membros = m;
      pagamentos = pg;
      if (m.isEmpty) {
        rondaSel = 0;
      } else if (rondaSel >= m.length) {
        rondaSel = m.length - 1;
      }
      // Na primeira vez abre na primeira ronda ainda incompleta
      if (_primeira && m.isNotEmpty) {
        _primeira = false;
        final c = Calc(widget.grupo, m, pg);
        rondaSel = List.generate(m.length, (i) => i)
            .firstWhere((i) => !c.completa(i), orElse: () => 0);
      }
    });
  }

  // Acoes dos membros

  Future<void> novoMembro() async {
    final nomeCtrl = TextEditingController();
    final telCtrl = TextEditingController();
    final pedidoCtrl = TextEditingController();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo membro'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nomeCtrl,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              TextField(
                controller: telCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Telefone'),
              ),
              if (modo == 2)
                TextField(
                  controller: pedidoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Ronda em que quer receber (numero)',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (guardar == true) {
      final nome = nomeCtrl.text.trim();
      if (nome.isNotEmpty) {
        final pedido = int.tryParse(pedidoCtrl.text.trim());
        await Db.criarMembro(grupoId, nome, telCtrl.text.trim(), pedido);
        await carregar();
      }
    }
  }

  // Sorteia a ordem de recebimento com a roleta
  Future<void> sortear() async {
    if (membros.length < 2) {
      aviso(context, 'Precisas de pelo menos 2 membros.');
      return;
    }
    final ordem = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RoletaDialog(membros: membros),
    );
    if (ordem != null) {
      await Db.guardarOrdem(ordem);
      await carregar();
    }
  }

  // Troca a posicao de dois membros
  Future<void> trocar() async {
    if (membros.length < 2) {
      aviso(context, 'Precisas de pelo menos 2 membros.');
      return;
    }
    int a = membros[0]['id'] as int;
    int b = membros[1]['id'] as int;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Trocar posicoes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: a,
                isExpanded: true,
                items: membros
                    .map((m) => DropdownMenuItem<int>(
                          value: m['id'] as int,
                          child: Text(m['nome'].toString()),
                        ))
                    .toList(),
                onChanged: (v) => setD(() => a = v ?? a),
              ),
              const Icon(Icons.swap_vert),
              DropdownButton<int>(
                value: b,
                isExpanded: true,
                items: membros
                    .map((m) => DropdownMenuItem<int>(
                          value: m['id'] as int,
                          child: Text(m['nome'].toString()),
                        ))
                    .toList(),
                onChanged: (v) => setD(() => b = v ?? b),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Trocar'),
            ),
          ],
        ),
      ),
    );

    if (ok == true && a != b) {
      final ids = membros.map((m) => m['id'] as int).toList();
      final ia = ids.indexOf(a);
      final ib = ids.indexOf(b);
      ids[ia] = b;
      ids[ib] = a;
      await Db.guardarOrdem(ids);
      await carregar();
    }
  }

  // Aplica as escolhas de cada membro; empates sao sorteados
  Future<void> resolverEscolhas() async {
    final n = membros.length;
    if (n < 2) {
      aviso(context, 'Precisas de pelo menos 2 membros.');
      return;
    }
    final rnd = Random();
    final slots = List<Map<String, dynamic>?>.filled(n, null);
    final pedidos = <int, List<Map<String, dynamic>>>{};
    final sobras = <Map<String, dynamic>>[];
    final relatorio = <String>[];

    for (final m in membros) {
      final pr = m['pedido_ronda'];
      if (pr is int && pr >= 1 && pr <= n) {
        pedidos.putIfAbsent(pr, () => []).add(m);
      } else {
        sobras.add(m);
      }
    }

    final chaves = pedidos.keys.toList()..sort();
    for (final r in chaves) {
      final lista = pedidos[r]!;
      lista.shuffle(rnd);
      slots[r - 1] = lista.first;
      if (lista.length > 1) {
        relatorio.add('Ronda $r: sorteio entre '
            '${lista.map((m) => m['nome']).join(', ')}. '
            'Ganhou ${lista.first['nome']}.');
        sobras.addAll(lista.skip(1));
      }
    }

    var j = 0;
    for (var i = 0; i < n; i++) {
      if (slots[i] == null) {
        slots[i] = sobras[j];
        j++;
      }
    }

    await Db.guardarOrdem(slots.map((m) => m!['id'] as int).toList());
    await carregar();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Escolhas aplicadas'),
        content: Text(relatorio.isEmpty
            ? 'Nao houve empates. Quem nao escolheu ficou nas vagas livres.'
            : '${relatorio.join('\n')}\n\nQuem perdeu o sorteio ou nao escolheu ficou nas vagas livres.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Abre o ecra de pagamentos de um membro numa ronda
  Future<void> abrirPagamentos(Map<String, dynamic> m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PagamentosMembroPage(
          grupo: widget.grupo,
          membro: m,
          ronda: rondaSel,
        ),
      ),
    );
    await carregar();
  }

  // Abre o perfil de um membro
  Future<void> abrirPerfil(Map<String, dynamic> m) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PerfilMembroPage(grupo: widget.grupo, membroId: m['id'] as int),
      ),
    );
    await carregar();
  }

  // Separador 1: membros
  Widget separadorMembros() {
    final c = calc;
    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [
                      Text('${formatarValor(c.valor)} MZN',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text('por pessoa'),
                    ]),
                    Column(children: [
                      Text('${formatarValor(c.esperadoRonda)} MZN',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const Text('total por ronda'),
                    ]),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Ordem: ${textoModo(modo)} | '
                    'multa ${formatarValor(c.multaPct)}% | '
                    'fundo ${formatarValor(c.fundoPct)}%'),
              ],
            ),
          ),
        ),
        Expanded(
          child: membros.isEmpty
              ? const Center(
                  child: Text(
                    'Ainda nao ha membros.\nCarrega no botao para adicionar.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.builder(
                  itemCount: membros.length,
                  itemBuilder: (context, i) {
                    final m = membros[i];
                    final ativo = c.ativo(m);
                    final tel = (m['telefone'] ?? '').toString();
                    String sub = tel.isEmpty ? 'Sem telefone' : tel;
                    if (modo == 2 && m['pedido_ronda'] != null) {
                      sub += ' | pediu ronda ${m['pedido_ronda']}';
                    }
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(
                          ativo ? m['nome'] : '${m['nome']} (desistiu)',
                          style: TextStyle(
                            color: ativo ? null : Colors.grey,
                            decoration:
                                ativo ? null : TextDecoration.lineThrough,
                          ),
                        ),
                        subtitle: Text(sub),
                        // Tocar abre o perfil do membro
                        onTap: () => abrirPerfil(m),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'ativo') {
                              if (ativo) {
                                final ok = await confirmar(
                                    context,
                                    'Marcar "${m['nome']}" como desistiu? '
                                    'Deixa de pagar as proximas rondas.',
                                    botao: 'Confirmar');
                                if (!ok) return;
                              }
                              await Db.definirAtivo(m['id'], !ativo);
                              await carregar();
                            } else if (v == 'eliminar') {
                              final ok = await confirmar(context,
                                  'Eliminar "${m['nome']}" e os pagamentos dele?');
                              if (ok) {
                                await Db.eliminarMembro(m['id']);
                                await carregar();
                              }
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'ativo',
                              child: Text(
                                  ativo ? 'Marcar como desistiu' : 'Reativar'),
                            ),
                            const PopupMenuItem(
                              value: 'eliminar',
                              child: Text('Eliminar'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Separador 2: pagamentos
  Widget separadorPagamentos() {
    if (membros.isEmpty) {
      return const Center(
        child: Text(
          'Adiciona membros primeiro\nno separador Membros.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final c = calc;
    final total = membros.length;
    final recebe = membros[rondaSel];
    final data = dataDaRonda(widget.grupo, rondaSel);
    final bruto = c.brutoRonda(rondaSel);
    final esperado = c.esperadoRonda;
    final progresso =
        esperado > 0 ? (bruto / esperado).clamp(0.0, 1.0).toDouble() : 0.0;

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<int>(
                  value: rondaSel,
                  isExpanded: true,
                  items: List.generate(
                    total,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text(
                        'Ronda ${i + 1} de $total - ${membros[i]['nome']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  onChanged: (v) => setState(() => rondaSel = v ?? 0),
                ),
                const SizedBox(height: 8),
                Text('Recebe: ${recebe['nome']}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Data da ronda: ${formatarData(data)}'),
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progresso),
                const SizedBox(height: 6),
                Text('${formatarValor(bruto)} de ${formatarValor(esperado)} '
                    'MZN confirmados'),
                if (c.fundoPct > 0)
                  Text('Recebe liquido: '
                      '${formatarValor(c.recebidoRonda(rondaSel))} MZN '
                      '(fundo ${formatarValor(c.fundoPct)}%)'),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: total,
            itemBuilder: (context, i) {
              final m = membros[i];
              if (!c.ativo(m)) {
                return ListTile(
                  enabled: false,
                  leading: const Icon(Icons.person_off),
                  title: Text(m['nome']),
                  subtitle: const Text('Desistiu'),
                );
              }
              final e = c.estado(m['id'], rondaSel);
              return ListTile(
                leading: e == 2
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : e == 1
                        ? const Icon(Icons.timelapse, color: Colors.orange)
                        : const Icon(Icons.radio_button_unchecked),
                title: Text(m['nome']),
                subtitle: Text(textoEstado(c, m, rondaSel)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => abrirPagamentos(m),
              );
            },
          ),
        ),
      ],
    );
  }

  // Separador 3: calendario
  Widget separadorCalendario() {
    if (membros.isEmpty) {
      return const Center(
        child: Text(
          'Adiciona membros primeiro\npara ver o calendario.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final c = calc;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: membros.length,
      itemBuilder: (context, i) {
        final m = membros[i];
        final completa = c.completa(i);
        final esperado = c.esperadoRonda;
        final pct = esperado > 0
            ? (c.brutoRonda(i) / esperado * 100).clamp(0.0, 100.0).round()
            : 0;
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(c.ativo(m) ? m['nome'] : '${m['nome']} (desistiu)'),
            subtitle: Text(
              '${formatarData(dataDaRonda(widget.grupo, i))}  |  '
              'recebe ${formatarValor(esperado * (1 - c.fundoPct / 100))} MZN',
            ),
            trailing: completa
                ? const Icon(Icons.check_circle, color: Colors.green)
                : Text('$pct%'),
          ),
        );
      },
    );
  }

  // Separador 4: painel
  Widget separadorPainel() {
    if (membros.isEmpty) {
      return const Center(
        child: Text(
          'Adiciona membros primeiro\npara ver o painel.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final c = calc;
    final cor = Theme.of(context).colorScheme.primary;

    final ranking = List<Map<String, dynamic>>.from(membros);
    ranking.sort((a, b) {
      final sa = c.score(a) ?? -1;
      final sb = c.score(b) ?? -1;
      return sb.compareTo(sa);
    });

    final desistentes = <int>[];
    for (var i = 0; i < membros.length; i++) {
      if (!c.ativo(membros[i])) desistentes.add(i);
    }

    Widget numero(String valor, String legenda) {
      return SizedBox(
        width: 140,
        child: Column(children: [
          Text(valor,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          Text(legenda, textAlign: TextAlign.center),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              runSpacing: 14,
              alignment: WrapAlignment.spaceAround,
              children: [
                numero('${formatarValor(c.totalConf)} MZN', 'recolhido'),
                numero('${formatarValor(c.fundo)} MZN', 'fundo de reserva'),
                numero('${formatarValor(c.multasTotal)} MZN', 'multas devidas'),
                numero('${formatarValor(c.totalPend)} MZN', 'por confirmar'),
              ],
            ),
          ),
        ),

        // Grafico de barras: percentagem paga por ronda
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pagamento por ronda',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 130,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: List.generate(membros.length, (i) {
                      final e = c.esperadoRonda;
                      final pct = e > 0
                          ? (c.brutoRonda(i) / e).clamp(0.0, 1.0).toDouble()
                          : 0.0;
                      return SizedBox(
                        width: 46,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('${(pct * 100).round()}%',
                                style: const TextStyle(fontSize: 10)),
                            const SizedBox(height: 4),
                            Container(
                              width: 24,
                              height: 2 + 78 * pct,
                              decoration: BoxDecoration(
                                color: cor,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('R${i + 1}',
                                style: const TextStyle(fontSize: 11)),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Ranking de confianca
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Score de confianca',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const Text('Pagamentos a tempo sobre o total',
                    style: TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                ...ranking.map((m) {
                  final s = c.score(m);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Text(m['nome'].toString(),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Expanded(
                          flex: 4,
                          child: LinearProgressIndicator(
                            value: s == null ? 0 : s / 100,
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: Text(
                            s == null ? 'sem dados' : '${s.round()}%',
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        if (desistentes.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Desistencias',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...desistentes.map((i) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text('${membros[i]['nome']}: ${c.acerto(i)}'),
                      )),
                ],
              ),
            ),
          ),

        // Copiar o resumo da ronda
        FilledButton.icon(
          icon: const Icon(Icons.copy),
          label: Text('Copiar resumo da ronda ${rondaSel + 1}'),
          onPressed: () async {
            await Clipboard.setData(
                ClipboardData(text: c.resumoRonda(rondaSel)));
            if (!mounted) return;
            aviso(context, 'Resumo copiado. Cola no WhatsApp.');
          },
        ),
        // Copiar o relatorio completo do grupo
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.description),
          label: const Text('Copiar relatorio completo'),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: c.relatorioCompleto()));
            if (!mounted) return;
            aviso(context, 'Relatorio copiado.');
          },
        ),
        // Enviar o resumo pelo WhatsApp (so no Android)
        if (ehAndroid) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.chat),
            label: Text('Enviar resumo da ronda ${rondaSel + 1} por WhatsApp'),
            onPressed: () => abrirLink(context,
                'https://wa.me/?text=${Uri.encodeComponent(c.resumoRonda(rondaSel))}'),
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.grupo['nome']),
        actions: _tab.index == 0
            ? [
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'sorteio') sortear();
                    if (v == 'troca') trocar();
                    if (v == 'escolhas') resolverEscolhas();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'sorteio', child: Text('Roleta: sortear ordem')),
                    const PopupMenuItem(
                        value: 'troca', child: Text('Trocar posicoes')),
                    if (modo == 2)
                      const PopupMenuItem(
                          value: 'escolhas',
                          child: Text('Aplicar escolhas (sorteia empates)')),
                  ],
                ),
              ]
            : null,
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Membros'),
            Tab(icon: Icon(Icons.payments), text: 'Pagamentos'),
            Tab(icon: Icon(Icons.event), text: 'Calendario'),
            Tab(icon: Icon(Icons.insights), text: 'Painel'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          separadorMembros(),
          separadorPagamentos(),
          separadorCalendario(),
          separadorPainel(),
        ],
      ),
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton(
              onPressed: novoMembro,
              child: const Icon(Icons.person_add),
            )
          : null,
    );
  }
}

// Ecra: perfil de um membro
class PerfilMembroPage extends StatefulWidget {
  final Map<String, dynamic> grupo;
  final int membroId;

  const PerfilMembroPage(
      {super.key, required this.grupo, required this.membroId});

  @override
  State<PerfilMembroPage> createState() => _PerfilMembroPageState();
}

class _PerfilMembroPageState extends State<PerfilMembroPage> {
  List<Map<String, dynamic>> membros = [];
  List<Map<String, dynamic>> pagamentos = [];
  bool carregado = false;

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final gid = widget.grupo['id'] as int;
    final m = await Db.listarMembros(gid);
    final pg = await Db.listarPagamentos(gid);
    if (!mounted) return;
    setState(() {
      membros = m;
      pagamentos = pg;
      carregado = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!carregado) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final idx = membros.indexWhere((m) => m['id'] == widget.membroId);
    if (idx < 0) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Membro nao encontrado.')),
      );
    }

    final c = Calc(widget.grupo, membros, pagamentos);
    final m = membros[idx];
    final sc = c.score(m);
    final tel = (m['telefone'] ?? '').toString();
    final mensagem = c.mensagemCobranca(m);

    return Scaffold(
      appBar: AppBar(title: Text(m['nome'])),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.ativo(m) ? 'Membro ativo' : 'Desistiu',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Telefone: ${tel.isEmpty ? '-' : tel}'),
                  Text('Recebe na ronda ${idx + 1} em '
                      '${formatarData(dataDaRonda(widget.grupo, idx))}'
                      '${c.completa(idx) ? ' (ronda completa)' : ''}'),
                  const Divider(height: 24),
                  Text('Total pago: ${formatarValor(c.pagoPor(m['id']))} MZN'),
                  Text('Rondas em atraso: ${c.atrasos(m)}'),
                  Text('Multa devida: ${formatarValor(c.multaDe(m))} MZN'),
                  Text('Score de confianca: '
                      '${sc == null ? 'sem dados' : '${sc.round()}%'}'),
                ],
              ),
            ),
          ),
          if (ehAndroid)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Cobrar valores em atraso'),
                onPressed: () {
                  if (mensagem == null) {
                    aviso(context, 'Nao ha valores em atraso.');
                  } else {
                    cobrar(context, tel, mensagem);
                  }
                },
              ),
            ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text('Historico por ronda',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          ...List.generate(c.rondas, (r) {
            final e = c.estado(m['id'], r);
            return ListTile(
              dense: true,
              leading: e == 2
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : e == 1
                      ? const Icon(Icons.timelapse, color: Colors.orange)
                      : const Icon(Icons.radio_button_unchecked),
              title: Text('Ronda ${r + 1} - '
                  '${formatarData(dataDaRonda(widget.grupo, r))}'),
              subtitle: Text(textoEstado(c, m, r)),
            );
          }),
        ],
      ),
    );
  }
}

// Ecra 3: pagamentos de um membro numa ronda
class PagamentosMembroPage extends StatefulWidget {
  final Map<String, dynamic> grupo;
  final Map<String, dynamic> membro;
  final int ronda;

  const PagamentosMembroPage({
    super.key,
    required this.grupo,
    required this.membro,
    required this.ronda,
  });

  @override
  State<PagamentosMembroPage> createState() => _PagamentosMembroPageState();
}

class _PagamentosMembroPageState extends State<PagamentosMembroPage> {
  List<Map<String, dynamic>> lista = [];

  int get grupoId => widget.grupo['id'] as int;
  int get membroId => widget.membro['id'] as int;
  double get valor => (widget.grupo['valor'] as num).toDouble();
  String get numeroGrupo => (widget.grupo['numero_recebe'] ?? '').toString();

  @override
  void initState() {
    super.initState();
    carregar();
  }

  Future<void> carregar() async {
    final d = await Db.listarPagamentosMembroRonda(membroId, widget.ronda);
    if (!mounted) return;
    setState(() => lista = d);
  }

  // Janela para registar um pagamento novo
  Future<void> registar() async {
    final msgCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final refCtrl = TextEditingController();
    DateTime data = DateTime.now();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Registar pagamento'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: msgCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Colar mensagem M-Pesa / e-Mola',
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.auto_fix_high),
                    label: const Text('Extrair dados'),
                    onPressed: () {
                      final r = extrairMensagem(msgCtrl.text);
                      setD(() {
                        if (r.valor != null) {
                          valorCtrl.text = formatarValor(r.valor!);
                        }
                        if (r.referencia != null) {
                          refCtrl.text = r.referencia!;
                        }
                      });
                    },
                  ),
                ),
                TextField(
                  controller: valorCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor (MZN)'),
                ),
                TextField(
                  controller: refCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Referencia da transacao',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: Text('Data: ${formatarData(data)}'),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: data,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2040),
                    );
                    if (d != null) setD(() => data = d);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'So fica CONFIRMADO com uma mensagem valida. Sem mensagem, fica NAO CONFIRMADO e nao conta.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final v = double.tryParse(valorCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    var ref = refCtrl.text.trim().toUpperCase();
    final msg = msgCtrl.text.trim();
    bool confirmado = false;

    if (v <= 0) {
      if (!mounted) return;
      aviso(context, 'Valor invalido.');
      return;
    }

    if (msg.isNotEmpty) {
      // Ha mensagem: valida-a
      final r =
          validarMensagem(msg, valorDigitado: v, numeroRecebe: numeroGrupo);
      if (!r.ok) {
        if (!mounted) return;
        await mostrarErros(context, 'Mensagem nao aceite', r.erros);
        return;
      }
      if (ref.isNotEmpty && ref != r.referencia) {
        if (!mounted) return;
        await mostrarErros(context, 'Mensagem nao aceite', [
          'A referencia digitada ($ref) e diferente da da mensagem (${r.referencia}).'
        ]);
        return;
      }
      ref = r.referencia!;
      confirmado = r.avisos.isEmpty;
      if (r.avisos.isNotEmpty && mounted) {
        await mostrarErros(context, 'Guardado como NAO CONFIRMADO', r.avisos);
      }
    } else if (ref.isNotEmpty && !referenciaValida(ref)) {
      if (!mounted) return;
      aviso(context, 'Referencia invalida (8 a 14 letras e numeros).');
      return;
    }

    // A mesma referencia nao pode ser usada duas vezes
    if (ref.isNotEmpty && await Db.referenciaExiste(ref)) {
      if (!mounted) return;
      aviso(context, 'Esta referencia ja foi usada num pagamento.');
      return;
    }
    await Db.criarPagamento(
        grupoId, membroId, widget.ronda, v, data, ref, msg, confirmado);
    await carregar();
  }

  // Confirma um pagamento colando a mensagem
  Future<void> confirmarPag(Map<String, dynamic> pg) async {
    final msgCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pagamento'),
        content: TextField(
          controller: msgCtrl,
          maxLines: 4,
          decoration: const InputDecoration(
            labelText: 'Cola a mensagem M-Pesa / e-Mola',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final msg = msgCtrl.text.trim();
    final r = validarMensagem(msg,
        valorDigitado: (pg['valor'] as num).toDouble(),
        numeroRecebe: numeroGrupo);
    if (!mounted) return;
    if (!r.ok) {
      await mostrarErros(context, 'Mensagem nao aceite', r.erros);
      return;
    }
    if (r.avisos.isNotEmpty) {
      await mostrarErros(context, 'Nao foi confirmado', r.avisos);
      return;
    }
    if (await Db.referenciaExiste(r.referencia!, ignorarId: pg['id'] as int)) {
      if (!mounted) return;
      aviso(context, 'Esta referencia ja foi usada noutro pagamento.');
      return;
    }
    await Db.confirmarPagamento(pg['id'], r.referencia!, msg);
    await carregar();
  }

  @override
  Widget build(BuildContext context) {
    double confirmado = 0;
    double pendente = 0;
    for (final x in lista) {
      final v = (x['valor'] as num).toDouble();
      if (x['confirmado'] == 1) {
        confirmado += v;
      } else {
        pendente += v;
      }
    }
    final progresso =
        valor > 0 ? (confirmado / valor).clamp(0.0, 1.0).toDouble() : 0.0;
    final tel = (widget.membro['telefone'] ?? '').toString();

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.membro['nome']} - ronda ${widget.ronda + 1}'),
        actions: ehAndroid
            ? [
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: 'Cobrar',
                  onPressed: () {
                    final falta = valor - confirmado;
                    if (falta <= 0.001) {
                      aviso(context, 'Este membro ja pagou esta ronda.');
                      return;
                    }
                    cobrar(
                      context,
                      tel,
                      'Ola ${widget.membro['nome']}, lembrete do xitique '
                      '"${widget.grupo['nome']}": falta ${formatarValor(falta)} MZN '
                      'da ronda ${widget.ronda + 1} (vencimento '
                      '${formatarData(dataDaRonda(widget.grupo, widget.ronda))}). '
                      'Obrigado!',
                    );
                  },
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Deve pagar ${formatarValor(valor)} MZN',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Vencimento: '
                      '${formatarData(dataDaRonda(widget.grupo, widget.ronda))}'),
                  const SizedBox(height: 10),
                  LinearProgressIndicator(value: progresso),
                  const SizedBox(height: 6),
                  Text('Confirmado: ${formatarValor(confirmado)} de '
                      '${formatarValor(valor)} MZN'),
                  if (pendente > 0)
                    Text('Por confirmar: ${formatarValor(pendente)} MZN'),
                ],
              ),
            ),
          ),
          Expanded(
            child: lista.isEmpty
                ? const Center(
                    child: Text('Ainda nao ha pagamentos nesta ronda.'),
                  )
                : ListView.builder(
                    itemCount: lista.length,
                    itemBuilder: (context, i) {
                      final x = lista[i];
                      final conf = x['confirmado'] == 1;
                      final d = DateTime.tryParse(x['data'].toString());
                      final ref = (x['referencia'] ?? '').toString();
                      return Card(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: conf
                              ? const Icon(Icons.verified, color: Colors.green)
                              : const Icon(Icons.hourglass_empty,
                                  color: Colors.orange),
                          title: Text('${formatarValor(x['valor'] as num)} MZN'),
                          subtitle: Text(
                            '${d == null ? '' : formatarData(d)} | '
                            '${conf ? 'ref $ref' : 'NAO CONFIRMADO${ref.isEmpty ? '' : ' (ref $ref)'}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!conf)
                                IconButton(
                                  icon: const Icon(Icons.check),
                                  tooltip: 'Confirmar com mensagem',
                                  onPressed: () => confirmarPag(x),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete),
                                onPressed: () async {
                                  final ok = await confirmar(
                                      context, 'Eliminar este pagamento?');
                                  if (ok) {
                                    await Db.eliminarPagamento(x['id']);
                                    await carregar();
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: registar,
        icon: const Icon(Icons.add),
        label: const Text('Registar pagamento'),
      ),
    );
  }
}