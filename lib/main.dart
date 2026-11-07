// XITIQUE DIGITAL - Fase A
// Grupos, membros, pagamentos com confirmacao, multa, fundo,
// ordem (entrada / sorteio / escolha), desistencia e painel


import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// Usamos "as p" para evitar conflito com o "context" do Flutter
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Funcao principal: e aqui que a app comeca
void main() {
  runApp(const XitiqueApp());
}

// FUNCOES AUXILIARES


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

// Resultado da leitura de uma mensagem M-Pesa / e-Mola
class ExtraidoMsg {
  final double? valor;
  final String? referencia;
  ExtraidoMsg(this.valor, this.referencia);
}

// Tenta encontrar o valor e a referencia numa mensagem copiada
// Atencao: e uma leitura simples, o utilizador deve sempre conferir
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

  // Procura um codigo de 8 a 14 caracteres com letras e numeros
  final rr = RegExp(r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*\d)[A-Z0-9]{8,14}\b');
  final mr = rr.firstMatch(texto);
  if (mr != null) ref = mr.group(0);

  return ExtraidoMsg(valor, ref);
}


// CALCULOS (multa, fundo, score, estados)
// Recebe os dados ja carregados e calcula tudo em memoria

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

  // Multa total devida por um membro (todas as rondas atrasadas)
  double multaDe(Map<String, dynamic> m) {
    if (multaPct <= 0) return 0;
    double total = 0;
    for (var r = 0; r < rondas; r++) {
      if (pontualidade(m, r) == 1) total += valor * multaPct / 100;
    }
    return total;
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


// WIDGET RAIZ DA APP

class XitiqueApp extends StatelessWidget {
  const XitiqueApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Xitique Digital',
      debugShowCheckedModeBanner: false, // esconde a faixa "debug"
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const GruposPage(), // primeiro ecra a ser mostrado
    );
  }
}

// BASE DE DADOS (SQLite) - versao 4

class Db {
  // Guarda a ligacao a base de dados para nao abrir varias vezes
  static Database? _db;

  static Future<Database> abrir() async {
    if (_db != null) return _db!;

    // Caminho do ficheiro da base de dados no telemovel
    final caminho = p.join(await getDatabasesPath(), 'xitique.db');

    _db = await openDatabase(
      caminho,
      version: 4,
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
          'modo_ordem INTEGER DEFAULT 0)',
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
          // Colunas novas dos grupos
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN multa_pct REAL DEFAULT 0');
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN fundo_pct REAL DEFAULT 0');
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN modo_ordem INTEGER DEFAULT 0');
          // Colunas novas dos membros
          await db.execute(
              'ALTER TABLE membros ADD COLUMN posicao INTEGER DEFAULT 0');
          await db.execute(
              'ALTER TABLE membros ADD COLUMN ativo INTEGER DEFAULT 1');
          await db.execute('ALTER TABLE membros ADD COLUMN pedido_ronda INTEGER');
          // Os membros antigos ficam na ordem em que foram criados
          await db.execute('UPDATE membros SET posicao = id');
          // Tabela nova de pagamentos
          await _criarTabelaPagamentos(db);
          // Se vinha da versao 3, converte as contribuicoes antigas
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
      },
    );
    return _db!;
  }

  // Cada pagamento e um registo: quem, que ronda, quanto, quando, referencia
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

  // GRUPOS 

  // Devolve todos os grupos, com o total de membros de cada um
  static Future<List<Map<String, dynamic>>> listarGrupos() async {
    final db = await abrir();
    return db.rawQuery(
      'SELECT g.*, '
      '(SELECT COUNT(*) FROM membros m WHERE m.grupo_id = g.id) '
      'AS total_membros '
      'FROM grupos g ORDER BY g.id DESC',
    );
  }

  // Insere um grupo novo
  static Future<void> criarGrupo(String nome, double valor, int periodo,
      DateTime inicio, double multa, double fundo, int modo) async {
    final db = await abrir();
    await db.insert('grupos', {
      'nome': nome,
      'valor': valor,
      'periodo': periodo,
      'data_inicio': inicio.toIso8601String(),
      'multa_pct': multa,
      'fundo_pct': fundo,
      'modo_ordem': modo,
    });
  }

  // Apaga o grupo e tudo o que pertence a ele
  static Future<void> eliminarGrupo(int id) async {
    final db = await abrir();
    await db.delete('pagamentos', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('membros', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('grupos', where: 'id = ?', whereArgs: [id]);
  }

  // MEMBROS 

  // Devolve os membros pela ordem de recebimento
  static Future<List<Map<String, dynamic>>> listarMembros(int grupoId) async {
    final db = await abrir();
    return db.query(
      'membros',
      where: 'grupo_id = ?',
      whereArgs: [grupoId],
      orderBy: 'posicao ASC, id ASC',
    );
  }

  // Insere um membro novo no fim da fila
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

  // Apaga o membro e os pagamentos dele
  static Future<void> eliminarMembro(int id) async {
    final db = await abrir();
    await db.delete('pagamentos', where: 'membro_id = ?', whereArgs: [id]);
    await db.delete('membros', where: 'id = ?', whereArgs: [id]);
  }

  // Marca o membro como ativo (true) ou desistiu (false)
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

  // PAGAMENTOS 

  // Todos os pagamentos de um grupo
  static Future<List<Map<String, dynamic>>> listarPagamentos(
      int grupoId) async {
    final db = await abrir();
    return db.query('pagamentos',
        where: 'grupo_id = ?', whereArgs: [grupoId], orderBy: 'data ASC');
  }

  // Pagamentos de um membro numa ronda
  static Future<List<Map<String, dynamic>>> listarPagamentosMembroRonda(
      int membroId, int ronda) async {
    final db = await abrir();
    return db.query('pagamentos',
        where: 'membro_id = ? AND ronda = ?',
        whereArgs: [membroId, ronda],
        orderBy: 'data ASC');
  }

  // Verifica se uma referencia ja foi usada
  static Future<bool> referenciaExiste(String ref) async {
    final db = await abrir();
    final r = await db.query('pagamentos',
        where: 'referencia = ?', whereArgs: [ref], limit: 1);
    return r.isNotEmpty;
  }

  static Future<void> criarPagamento(int grupoId, int membroId, int ronda,
      double valor, DateTime data, String ref) async {
    final db = await abrir();
    await db.insert('pagamentos', {
      'grupo_id': grupoId,
      'membro_id': membroId,
      'ronda': ronda,
      'valor': valor,
      'data': data.toIso8601String(),
      'referencia': ref,
      'confirmado': ref.isNotEmpty ? 1 : 0,
    });
  }

  // Confirma um pagamento que estava sem referencia
  static Future<void> confirmarPagamento(int id, String ref) async {
    final db = await abrir();
    await db.update('pagamentos', {'referencia': ref, 'confirmado': 1},
        where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> eliminarPagamento(int id) async {
    final db = await abrir();
    await db.delete('pagamentos', where: 'id = ?', whereArgs: [id]);
  }
}


// ECRA 1: LISTA DE GRUPOS

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

  // Le os grupos da base de dados e atualiza o ecra
  Future<void> carregar() async {
    final dados = await Db.listarGrupos();
    if (!mounted) return;
    setState(() => grupos = dados);
  }

  // Mostra a janela para criar um grupo novo
  Future<void> novoGrupo() async {
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    final multaCtrl = TextEditingController(text: '0');
    final fundoCtrl = TextEditingController(text: '0');
    int periodo = 1; // 1 = mensal por defeito
    int modo = 0; // 0 = ordem de entrada
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
                // Periodo: mensal ou semanal
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
                // Modo da ordem de recebimento
                DropdownButtonFormField<int>(
                  value: modo,
                  isExpanded: true,
                  decoration:
                      const InputDecoration(labelText: 'Ordem de recebimento'),
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Ordem de entrada')),
                    DropdownMenuItem(value: 1, child: Text('Sorteio')),
                    DropdownMenuItem(
                        value: 2, child: Text('Cada um escolhe a ronda')),
                  ],
                  onChanged: (v) => setDialog(() => modo = v ?? 0),
                ),
                const SizedBox(height: 12),
                // Data de inicio
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

      // So guarda se o nome nao for vazio e o valor for maior que zero
      if (nome.isNotEmpty && valor > 0) {
        await Db.criarGrupo(nome, valor, periodo, inicio, multa, fundo, modo);
        await carregar();
      }
    }
  }

  // Abre o ecra do grupo escolhido
  Future<void> abrirGrupo(Map<String, dynamic> g) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GrupoPage(grupo: g)),
    );
    await carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xitique Digital')),
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


// JANELA DO SORTEIO (com animacao)

class SorteioDialog extends StatefulWidget {
  final List<Map<String, dynamic>> membros;

  const SorteioDialog({super.key, required this.membros});

  @override
  State<SorteioDialog> createState() => _SorteioDialogState();
}

class _SorteioDialogState extends State<SorteioDialog> {
  late List<Map<String, dynamic>> lista;
  Timer? _timer;
  int ticks = 0;
  bool terminou = false;
  final Random rnd = Random();

  @override
  void initState() {
    super.initState();
    lista = List.of(widget.membros);
    // A cada 120 ms embaralha a lista; depois de 16 vezes para
    _timer = Timer.periodic(const Duration(milliseconds: 120), (t) {
      ticks++;
      setState(() => lista.shuffle(rnd));
      if (ticks >= 16) {
        t.cancel();
        setState(() => terminou = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(terminou ? 'Ordem sorteada!' : 'A sortear...'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...List.generate(
                lista.length,
                (i) => ListTile(
                  dense: true,
                  leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
                  title: Text(lista[i]['nome'].toString()),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: terminou
              ? () => Navigator.pop(
                  context, lista.map((m) => m['id'] as int).toList())
              : null,
          child: const Text('Aceitar'),
        ),
      ],
    );
  }
}


// ECRA 2: DETALHES DO GRUPO (4 separadores)
// Membros | Pagamentos | Calendario | Painel

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
  int rondaSel = 0; // ronda escolhida (comeca em 0)
  bool _primeira = true; // para escolher a ronda inicial so uma vez

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

  // Le tudo da base de dados e atualiza o ecra
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

  // ACOES DOS MEMBROS 

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
              // So aparece se o grupo for do tipo "cada um escolhe"
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

  // Sorteia a ordem de recebimento com animacao
  Future<void> sortear() async {
    if (membros.length < 2) {
      aviso(context, 'Precisas de pelo menos 2 membros.');
      return;
    }
    final ordem = await showDialog<List<int>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SorteioDialog(membros: membros),
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

    // Separa quem pediu uma ronda valida de quem nao pediu
    for (final m in membros) {
      final pr = m['pedido_ronda'];
      if (pr is int && pr >= 1 && pr <= n) {
        pedidos.putIfAbsent(pr, () => []).add(m);
      } else {
        sobras.add(m);
      }
    }

    // Para cada ronda pedida, sorteia entre quem a quer
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

    // Preenche as vagas livres com quem sobrou
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

  //  SEPARADOR 1: MEMBROS 
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
                        // O numero e a ordem de recebimento
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

  //  SEPARADOR 2: PAGAMENTOS 
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
                // Escolha da ronda
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
              // Quem desistiu nao paga
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

  // SEPARADOR 3: CALENDARIO 
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

  // SEPARADOR 4: PAINEL 
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

    // Ranking de confianca: quem tem score primeiro, do maior para o menor
    final ranking = List<Map<String, dynamic>>.from(membros);
    ranking.sort((a, b) {
      final sa = c.score(a) ?? -1;
      final sb = c.score(b) ?? -1;
      return sb.compareTo(sa);
    });

    // Membros que desistiram
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
        // Numeros gerais
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

        // Acerto de quem desistiu
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

        // Copiar resumo da ronda atual
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
        const SizedBox(height: 24),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.grupo['nome']),
        // Menu de ordem so aparece no separador Membros
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
                        value: 'sorteio', child: Text('Sortear ordem')),
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

// ECRA 3: PAGAMENTOS DE UM MEMBRO NUMA RONDA

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
                // Mensagem de confirmacao copiada do telemovel
                TextField(
                  controller: msgCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Colar mensagem M-Pesa / e-Mola (opcional)',
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
                  'Sem referencia, o pagamento fica NAO CONFIRMADO e nao conta ate ser confirmado.',
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
    final ref = refCtrl.text.trim();
    if (v <= 0) {
      if (!mounted) return;
      aviso(context, 'Valor invalido.');
      return;
    }
    // A mesma referencia nao pode ser usada duas vezes
    if (ref.isNotEmpty && await Db.referenciaExiste(ref)) {
      if (!mounted) return;
      aviso(context, 'Esta referencia ja foi usada num pagamento.');
      return;
    }
    await Db.criarPagamento(grupoId, membroId, widget.ronda, v, data, ref);
    await carregar();
  }

  // Confirma um pagamento pedindo a referencia
  Future<void> confirmarPag(Map<String, dynamic> pg) async {
    final refCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar pagamento'),
        content: TextField(
          controller: refCtrl,
          decoration: const InputDecoration(
            labelText: 'Referencia da transacao',
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
    final ref = refCtrl.text.trim();
    if (ref.isEmpty) return;
    if (await Db.referenciaExiste(ref)) {
      if (!mounted) return;
      aviso(context, 'Esta referencia ja foi usada num pagamento.');
      return;
    }
    await Db.confirmarPagamento(pg['id'], ref);
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

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.membro['nome']} - ronda ${widget.ronda + 1}'),
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
                          title: Text(
                              '${formatarValor(x['valor'] as num)} MZN'),
                          subtitle: Text(
                            '${d == null ? '' : formatarData(d)} | '
                            '${conf ? 'ref $ref' : 'NAO CONFIRMADO'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!conf)
                                IconButton(
                                  icon: const Icon(Icons.check),
                                  tooltip: 'Confirmar',
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