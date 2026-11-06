
// XITIQUE DIGITAL - Versao 1: ecra de grupos com SQLite


import 'package:flutter/material.dart';
// Usamos "as p" para evitar conflito com o "context" do Flutter
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// Funcao principal: e aqui que a app comeca
void main() {
  runApp(const XitiqueApp());
}

// Widget raiz da app: define o titulo, o tema e o ecra inicial
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

  // Abre a base de dados (e cria a tabela na primeira vez)
  static Future<Database> abrir() async {
    // Se ja esta aberta, devolve a mesma
    if (_db != null) return _db!;

    // Caminho do ficheiro da base de dados no telemovel
    final caminho = p.join(await getDatabasesPath(), 'xitique.db');

    _db = await openDatabase(
      caminho,
      version: 1,
      // onCreate corre apenas quando a base de dados e criada
      onCreate: (db, versao) async {
        await db.execute(
          'CREATE TABLE grupos ('
          'id INTEGER PRIMARY KEY AUTOINCREMENT, '
          'nome TEXT NOT NULL, '
          'valor REAL NOT NULL)',
        );
      },
    );
    return _db!;
  }

  // Devolve todos os grupos, do mais recente para o mais antigo
  static Future<List<Map<String, dynamic>>> listarGrupos() async {
    final db = await abrir();
    return db.query('grupos', orderBy: 'id DESC');
  }

  // Insere um grupo novo na tabela
  static Future<void> criarGrupo(String nome, double valor) async {
    final db = await abrir();
    await db.insert('grupos', {'nome': nome, 'valor': valor});
  }

  // Apaga o grupo que tem o id indicado
  static Future<void> eliminarGrupo(int id) async {
    final db = await abrir();
    await db.delete('grupos', where: 'id = ?', whereArgs: [id]);
  }
}

// ECRA: LISTA DE GRUPOS

class GruposPage extends StatefulWidget {
  const GruposPage({super.key});

  @override
  State<GruposPage> createState() => _GruposPageState();
}

class _GruposPageState extends State<GruposPage> {
  // Lista de grupos que aparece no ecra
  List<Map<String, dynamic>> grupos = [];

  // initState corre uma vez, quando o ecra abre
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

    // Abre a janela de dialogo e espera pela resposta (true = guardar)
    final guardar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo grupo de xitique'),
        content: Column(
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
          ],
        ),
        actions: [
          // Botao cancelar: fecha a janela sem guardar
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          // Botao guardar: fecha a janela e devolve true
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    // Se o utilizador carregou em Guardar
    if (guardar == true) {
      final nome = nomeCtrl.text.trim(); // remove espacos extra
      final valor = double.tryParse(valorCtrl.text.trim()) ?? 0;

      // So guarda se o nome nao for vazio e o valor for maior que zero
      if (nome.isNotEmpty && valor > 0) {
        await Db.criarGrupo(nome, valor);
        await carregar(); // atualiza a lista no ecra
      }
    }
  }

  // Constroi o desenho do ecra
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barra do topo com o titulo
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
                    subtitle: Text('${g['valor']} MZN por ronda'),
                    // Botao do lixo: elimina o grupo
                    trailing: IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () async {
                        await Db.eliminarGrupo(g['id']);
                        await carregar(); // atualiza a lista
                      },
                    ),
                  ),
                );
              },
            ),

      // Botao flutuante + para criar um grupo novo
      floatingActionButton: FloatingActionButton(
        onPressed: novoGrupo,
        child: const Icon(Icons.add),
      ),
    );
  }
}