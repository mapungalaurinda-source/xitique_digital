
// XITIQUE DIGITAL - Versao completa
// Grupos, membros, contribuicoes e calendario (SQLite)


import 'package:flutter/material.dart';
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

// Texto do periodo: 0 = semanal, 1 = mensal
String textoPeriodo(int periodo) => periodo == 0 ? 'semanal' : 'mensal';

// Calcula a data de uma ronda (indice comeca em 0)
DateTime dataDaRonda(Map<String, dynamic> grupo, int indice) {
  final inicio =
      DateTime.tryParse((grupo['data_inicio'] ?? '').toString()) ??
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

// Janela de confirmacao (devolve true se o utilizador confirmar)
Future<bool> confirmar(BuildContext context, String texto) async {
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
          child: const Text('Eliminar'),
        ),
      ],
    ),
  );
  return r == true;
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


// BASE DE DADOS (SQLite)

class Db {
  // Guarda a ligacao a base de dados para nao abrir varias vezes
  static Database? _db;

  // Abre a base de dados (e cria ou atualiza as tabelas se for preciso)
  static Future<Database> abrir() async {
    if (_db != null) return _db!;

    // Caminho do ficheiro da base de dados no telemovel
    final caminho = p.join(await getDatabasesPath(), 'xitique.db');

    _db = await openDatabase(
      caminho,
      version: 3, // versao 3: grupos com data/periodo e contribuicoes
      // onCreate corre quando a base de dados e criada pela primeira vez
      onCreate: (db, versao) async {
        await db.execute(
          'CREATE TABLE grupos ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'nome TEXT NOT NULL, '
          'valor REAL NOT NULL, '
          'data_inicio TEXT, '
          'periodo INTEGER DEFAULT 1)',
        );
        await _criarTabelaMembros(db);
        await _criarTabelaContribuicoes(db);
      },
      // onUpgrade corre quando existe uma versao antiga da base de dados
      onUpgrade: (db, versaoAntiga, versaoNova) async {
        if (versaoAntiga < 2) {
          await _criarTabelaMembros(db);
        }
        if (versaoAntiga < 3) {
          // Acrescenta colunas novas aos grupos que ja existem
          await db.execute('ALTER TABLE grupos ADD COLUMN data_inicio TEXT');
          await db.execute(
              'ALTER TABLE grupos ADD COLUMN periodo INTEGER DEFAULT 1');
          await _criarTabelaContribuicoes(db);
        }
      },
    );
    return _db!;
  }

  // Cria a tabela de membros (cada membro pertence a um grupo)
  static Future<void> _criarTabelaMembros(Database db) async {
    await db.execute(
      'CREATE TABLE membros ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'grupo_id INTEGER NOT NULL, '
      'nome TEXT NOT NULL, '
      'telefone TEXT)',
    );
  }

  // Cria a tabela de contribuicoes: uma linha = um membro pagou uma ronda
  static Future<void> _criarTabelaContribuicoes(Database db) async {
    await db.execute(
      'CREATE TABLE contribuicoes ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'grupo_id INTEGER NOT NULL, '
      'membro_id INTEGER NOT NULL, '
      'ronda INTEGER NOT NULL, '
      'UNIQUE(membro_id, ronda))',
    );
  }

  //  GRUPOS

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

  // Insere um grupo novo na tabela
  static Future<void> criarGrupo(
      String nome, double valor, int periodo, DateTime inicio) async {
    final db = await abrir();
    await db.insert('grupos', {
      'nome': nome,
      'valor': valor,
      'periodo': periodo,
      'data_inicio': inicio.toIso8601String(),
    });
  }

  // Apaga o grupo e tudo o que pertence a ele
  static Future<void> eliminarGrupo(int id) async {
    final db = await abrir();
    await db.delete('contribuicoes', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('membros', where: 'grupo_id = ?', whereArgs: [id]);
    await db.delete('grupos', where: 'id = ?', whereArgs: [id]);
  }

  // MEMBROS 

  // Devolve os membros de um grupo, pela ordem em que foram adicionados
  static Future<List<Map<String, dynamic>>> listarMembros(int grupoId) async {
    final db = await abrir();
    return db.query(
      'membros',
      where: 'grupo_id = ?',
      whereArgs: [grupoId],
      orderBy: 'id ASC',
    );
  }

  // Insere um membro novo num grupo
  static Future<void> criarMembro(
      int grupoId, String nome, String telefone) async {
    final db = await abrir();
    await db.insert('membros', {
      'grupo_id': grupoId,
      'nome': nome,
      'telefone': telefone,
    });
  }

  // Apaga o membro e as contribuicoes dele
  static Future<void> eliminarMembro(int id) async {
    final db = await abrir();
    await db.delete('contribuicoes', where: 'membro_id = ?', whereArgs: [id]);
    await db.delete('membros', where: 'id = ?', whereArgs: [id]);
  }

  // CONTRIBUICOES

  // Devolve os ids dos membros que ja pagaram uma ronda
  static Future<Set<int>> pagantesDaRonda(int grupoId, int ronda) async {
    final db = await abrir();
    final linhas = await db.query(
      'contribuicoes',
      where: 'grupo_id = ? AND ronda = ?',
      whereArgs: [grupoId, ronda],
    );
    return linhas.map((l) => l['membro_id'] as int).toSet();
  }

  // Devolve quantos pagaram em cada ronda: {ronda: total}
  static Future<Map<int, int>> pagosPorRonda(int grupoId) async {
    final db = await abrir();
    final linhas = await db.rawQuery(
      'SELECT ronda, COUNT(*) AS total FROM contribuicoes '
      'WHERE grupo_id = ? GROUP BY ronda',
      [grupoId],
    );
    final mapa = <int, int>{};
    for (final l in linhas) {
      mapa[l['ronda'] as int] = l['total'] as int;
    }
    return mapa;
  }

  // Marca ou desmarca o pagamento de um membro numa ronda
  static Future<void> definirPagamento(
      int grupoId, int membroId, int ronda, bool pago) async {
    final db = await abrir();
    if (pago) {
      await db.insert(
        'contribuicoes',
        {'grupo_id': grupoId, 'membro_id': membroId, 'ronda': ronda},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await db.delete(
        'contribuicoes',
        where: 'membro_id = ? AND ronda = ?',
        whereArgs: [membroId, ronda],
      );
    }
  }
}


// ECRA 1: LISTA DE GRUPOS

class GruposPage extends StatefulWidget {
  const GruposPage({super.key});

  @override
  State<GruposPage> createState() => _GruposPageState();
}

class _GruposPageState extends State<GruposPage> {
  // Lista de grupos que aparece no ecra
  List<Map<String, dynamic>> grupos = [];

  @override
  void initState() {
    super.initState();
    carregar(); // carrega os grupos guardados
  }

  // Le os grupos da base de dados e atualiza o ecra
  Future<void> carregar() async {
    final dados = await Db.listarGrupos();
    setState(() => grupos = dados);
  }

  // Mostra a janela para criar um grupo novo
  Future<void> novoGrupo() async {
    // Controladores guardam o texto escrito nas caixas
    final nomeCtrl = TextEditingController();
    final valorCtrl = TextEditingController();
    int periodo = 1; // 1 = mensal por defeito
    DateTime inicio = DateTime.now();

    // StatefulBuilder permite atualizar a janela (periodo e data)
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('Novo grupo de xitique'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Caixa para o nome do grupo
                TextField(
                  controller: nomeCtrl,
                  decoration: const InputDecoration(labelText: 'Nome do grupo'),
                ),
                // Caixa para o valor da contribuicao (so numeros)
                TextField(
                  controller: valorCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Valor da contribuicao (MZN)',
                  ),
                ),
                const SizedBox(height: 16),
                // Escolha do periodo: mensal ou semanal
                DropdownButtonFormField<int>(
                  value: periodo,
                  decoration: const InputDecoration(labelText: 'Periodo'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Mensal')),
                    DropdownMenuItem(value: 0, child: Text('Semanal')),
                  ],
                  onChanged: (v) => setDialog(() => periodo = v ?? 1),
                ),
                const SizedBox(height: 12),
                // Escolha da data de inicio
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

    // Se o utilizador carregou em Guardar
    if (guardar == true) {
      final nome = nomeCtrl.text.trim();
      final valor = double.tryParse(valorCtrl.text.trim()) ?? 0;

      // So guarda se o nome nao for vazio e o valor for maior que zero
      if (nome.isNotEmpty && valor > 0) {
        await Db.criarGrupo(nome, valor, periodo, inicio);
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
    // Quando voltamos, recarrega para atualizar o total de membros
    await carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Xitique Digital')),

      // Se nao ha grupos, mostra uma mensagem; senao mostra a lista
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
                final g = grupos[i]; // grupo atual da lista
                return Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.groups),
                    title: Text(g['nome']),
                    subtitle: Text(
                      '${formatarValor(g['valor'])} MZN | '
                      '${textoPeriodo((g['periodo'] ?? 1) as int)} | '
                      '${g['total_membros']} membros',
                    ),
                    // Tocar no grupo abre os detalhes
                    onTap: () => abrirGrupo(g),
                    // Botao do lixo: elimina o grupo (com confirmacao)
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


// ECRA 2: DETALHES DO GRUPO (3 separadores)
// Membros | Contribuicoes | Calendario

class GrupoPage extends StatefulWidget {
  // Recebe o grupo escolhido no ecra anterior
  final Map<String, dynamic> grupo;

  const GrupoPage({super.key, required this.grupo});

  @override
  State<GrupoPage> createState() => _GrupoPageState();
}

class _GrupoPageState extends State<GrupoPage>
    with SingleTickerProviderStateMixin {
  // Controla os separadores (precisamos para mostrar o botao + so nos membros)
  late final TabController _tab;

  List<Map<String, dynamic>> membros = []; // membros do grupo
  Set<int> pagantes = {}; // ids dos que pagaram a ronda escolhida
  Map<int, int> pagosPorRonda = {}; // quantos pagaram em cada ronda
  int rondaSel = 0; // ronda escolhida (comeca em 0)

  // Atalhos para dados do grupo
  int get grupoId => widget.grupo['id'] as int;
  double get valor => (widget.grupo['valor'] as num).toDouble();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // Atualiza o ecra quando muda de separador
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
    // Se a ronda escolhida ja nao existe, volta a ultima
    if (m.isEmpty) {
      rondaSel = 0;
    } else if (rondaSel >= m.length) {
      rondaSel = m.length - 1;
    }
    final pagos = await Db.pagantesDaRonda(grupoId, rondaSel);
    final porRonda = await Db.pagosPorRonda(grupoId);
    setState(() {
      membros = m;
      pagantes = pagos;
      pagosPorRonda = porRonda;
    });
  }

  // Mostra a janela para adicionar um membro
  Future<void> novoMembro() async {
    final nomeCtrl = TextEditingController();
    final telCtrl = TextEditingController();

    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo membro'),
        content: Column(
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
          ],
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
      // O nome e obrigatorio
      if (nome.isNotEmpty) {
        await Db.criarMembro(grupoId, nome, telCtrl.text.trim());
        await carregar();
      }
    }
  }

  //  SEPARADOR 1: MEMBROS 
  Widget separadorMembros() {
    final totalRonda = valor * membros.length;

    return Column(
      children: [
        // Cartao de resumo no topo
        Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Column(children: [
                  Text('${formatarValor(valor)} MZN',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('por pessoa'),
                ]),
                Column(children: [
                  Text('${formatarValor(totalRonda)} MZN',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const Text('total por ronda'),
                ]),
              ],
            ),
          ),
        ),

        // Lista de membros
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
                    return Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      child: ListTile(
                        // O numero e a ordem de recebimento
                        leading: CircleAvatar(child: Text('${i + 1}')),
                        title: Text(m['nome']),
                        subtitle: Text(
                          (m['telefone'] ?? '').toString().isEmpty
                              ? 'Sem telefone'
                              : m['telefone'],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () async {
                            final ok = await confirmar(context,
                                'Eliminar o membro "${m['nome']}"?');
                            if (ok) {
                              await Db.eliminarMembro(m['id']);
                              await carregar();
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  //  SEPARADOR 2: CONTRIBUICOES 
  Widget separadorContribuicoes() {
    if (membros.isEmpty) {
      return const Center(
        child: Text(
          'Adiciona membros primeiro\nno separador Membros.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final total = membros.length;
    final pagos = pagantes.length;
    final recebe = membros[rondaSel]; // quem recebe nesta ronda
    final data = dataDaRonda(widget.grupo, rondaSel);

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
                      child: Text('Ronda ${i + 1} de $total'),
                    ),
                  ),
                  onChanged: (v) async {
                    rondaSel = v ?? 0;
                    await carregar();
                  },
                ),
                const SizedBox(height: 8),
                Text('Recebe: ${recebe['nome']}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Data: ${formatarData(data)}'),
                const SizedBox(height: 12),
                // Barra de progresso dos pagamentos
                LinearProgressIndicator(value: pagos / total),
                const SizedBox(height: 6),
                Text('$pagos de $total pagaram  |  '
                    '${formatarValor(valor * pagos)} de '
                    '${formatarValor(valor * total)} MZN'),
              ],
            ),
          ),
        ),

        // Lista com caixas para marcar quem pagou
        Expanded(
          child: ListView.builder(
            itemCount: total,
            itemBuilder: (context, i) {
              final m = membros[i];
              final pagou = pagantes.contains(m['id']);
              return CheckboxListTile(
                value: pagou,
                title: Text(m['nome']),
                subtitle: Text(pagou ? 'Pagou' : 'Em falta'),
                onChanged: (v) async {
                  await Db.definirPagamento(
                      grupoId, m['id'], rondaSel, v ?? false);
                  await carregar();
                },
              );
            },
          ),
        ),
      ],
    );
  }

  //  SEPARADOR 3: CALENDARIO 
  Widget separadorCalendario() {
    if (membros.isEmpty) {
      return const Center(
        child: Text(
          'Adiciona membros primeiro\npara ver o calendario.',
          textAlign: TextAlign.center,
        ),
      );
    }

    final total = membros.length;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: total,
      itemBuilder: (context, i) {
        final m = membros[i];
        final pagos = pagosPorRonda[i] ?? 0;
        final completa = pagos >= total; // todos pagaram esta ronda
        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: ListTile(
            leading: CircleAvatar(child: Text('${i + 1}')),
            title: Text(m['nome']),
            subtitle: Text(
              '${formatarData(dataDaRonda(widget.grupo, i))}  |  '
              'recebe ${formatarValor(valor * total)} MZN',
            ),
            // Icone verde se todos pagaram, senao mostra pagos/total
            trailing: completa
                ? const Icon(Icons.check_circle, color: Colors.green)
                : Text('$pagos/$total'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.grupo['nome']),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Membros'),
            Tab(icon: Icon(Icons.payments), text: 'Contribuicoes'),
            Tab(icon: Icon(Icons.event), text: 'Calendario'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          separadorMembros(),
          separadorContribuicoes(),
          separadorCalendario(),
        ],
      ),
      // O botao de adicionar membro so aparece no separador Membros
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton(
              onPressed: novoMembro,
              child: const Icon(Icons.person_add),
            )
          : null,
    );
  }
}