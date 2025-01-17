import 'package:bhima_collect/models/lot.dart';
import 'package:bhima_collect/models/stock_movement.dart';
import 'package:bhima_collect/providers/entry_movement.dart';
import 'package:bhima_collect/providers/exit_movement.dart';
import 'package:bhima_collect/services/db.dart';
import 'package:bhima_collect/utilities/util.dart';
import 'package:date_format/date_format.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:uuid/uuid.dart';

class StockExitPage extends StatefulWidget {
  StockExitPage({Key? key}) : super(key: key);

  @override
  State<StockExitPage> createState() => _StockExitPageState();
}

class _StockExitPageState extends State<StockExitPage> {
  var database = BhimaDatabase.open();
  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();
  final _STOCK_FROM_TO_PATIENT = 9;
  final PageController _controller = PageController(
    initialPage: 0,
  );

  final TextEditingController _txtDate = TextEditingController();
  final TextEditingController _txtReference = TextEditingController();
  final TextEditingController _txtQuantity = TextEditingController();

  String _selectedDepotUuid = '';
  String _selectedDepotText = '';
  int? _userId;
  bool _savingSucceed = false;

  DateTime _selectedDate = DateTime.now();
  final _customDateFormat = [dd, ' ', MM, ' ', yyyy];
  static const _kDuration = Duration(milliseconds: 300);
  static const _kCurve = Curves.ease;

  @override
  void initState() {
    super.initState();
    _loadSavedDepot();
  }

  @override
  void dispose() {
    _controller.dispose();
    _txtDate.dispose();
    _txtReference.dispose();
    _txtQuantity.dispose();
    super.dispose();
  }

  //Loading saved selected depot
  Future<void> _loadSavedDepot() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedDepotUuid = (prefs.getString('selected_depot_uuid') ?? '');
      _selectedDepotText = (prefs.getString('selected_depot_text') ?? '');
      _userId = prefs.getInt('user_id');
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> getPages() {
      List<Widget> pages = [];

      // Introduction page
      pages.add(Padding(
        padding: const EdgeInsets.all(16.0),
        child: stockExitStartPage(),
      ));

      // Lots pages
      Provider.of<ExitMovement>(context).createLots();
      for (var i = 0; i < Provider.of<ExitMovement>(context).totalItems; i++) {
        pages.add(Padding(
          padding: const EdgeInsets.all(16.0),
          child: lotExitPage(i),
        ));
      }

      // Introduction page
      pages.add(Padding(
        padding: const EdgeInsets.all(16.0),
        child: submitPage(),
      ));

      return pages;
    }

    var pageViews = Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.all(5),
          child: Center(
            child: Text(
              _selectedDepotText,
              style: TextStyle(
                fontSize: 20,
                color: Colors.blue[700],
              ),
            ),
          ),
        ),
        Expanded(
          child: PageView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            children: getPages(),
          ),
        ),
      ],
    );

    var pageBody = Form(
      key: _formKey,
      child: pageViews,
    );

    var pageBottom = Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ElevatedButton.icon(
            onPressed: () {
              _controller.previousPage(duration: _kDuration, curve: _kCurve);
            },
            label: const Text('Retour'),
            icon: const Icon(Icons.arrow_left_outlined),
          ),
          ElevatedButton.icon(
            onPressed: () {
              // Validate returns true if the form is valid, or false otherwise.
              if (_formKey.currentState!.validate()) {
                if (_controller.page == 0) {
                  Provider.of<ExitMovement>(context, listen: false)
                      .setDocumentReference = _txtReference.text;
                  Provider.of<ExitMovement>(context, listen: false)
                      .setTotalItems = int.parse(_txtQuantity.text);
                }
                _controller.nextPage(duration: _kDuration, curve: _kCurve);
              }
            },
            label: const Text('Suivant'),
            icon: const Icon(Icons.arrow_right_outlined),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sortie de stock'),
        leading: Builder(
          builder: (context) {
            return IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () {
                Navigator.pop(context, true);
              },
            );
          },
        ),
      ),
      body: pageBody,
      bottomNavigationBar: pageBottom,
    );
  }

  Widget inventoryTypeaheadField(int index) {
    final TextEditingController typeAheadController = TextEditingController();
    Future<List<Lot>> _loadInventories(String pattern) async {
      List<Lot> allLots = await Lot.inventories(database, _selectedDepotUuid);
      return allLots
          .where((element) =>
              element.text!.toLowerCase().contains(pattern.toLowerCase()) ==
              true)
          .toList();
    }

    return TypeAheadField(
      textFieldConfiguration: TextFieldConfiguration(
        controller: typeAheadController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Inventaire'),
      ),
      suggestionsCallback: (pattern) async {
        return _loadInventories(pattern);
      },
      itemBuilder: (context, Lot suggestion) {
        return Column(
          children: [
            ListTile(
              title: Text(suggestion.text ?? ''),
              subtitle: Text(suggestion.code ?? ''),
            ),
            const Divider(
              height: 2,
            )
          ],
        );
      },
      onSuggestionSelected: (Lot suggestion) {
        typeAheadController.text = suggestion.text ?? '';
        Provider.of<ExitMovement>(context, listen: false)
            .setLot(index, 'inventory_uuid', suggestion.inventory_uuid);
        Provider.of<ExitMovement>(context, listen: false)
            .setLot(index, 'inventory_text', suggestion.text);
      },
    );
  }

  Widget lotTypeaheadField(int index) {
    final TextEditingController lotTypeAheadController =
        TextEditingController();

    Future<List<Lot>> _loadInventoryLots(String pattern) async {
      var inventoryUuid = Provider.of<ExitMovement>(context)
          .getLotValue(index, 'inventory_uuid');
      List<Lot> allLots =
          await Lot.inventoryLots(database, _selectedDepotUuid, inventoryUuid);
      return allLots
          .where((element) => element.text?.contains(pattern) == true)
          .toList();
    }

    return TypeAheadField(
      textFieldConfiguration: TextFieldConfiguration(
        controller: lotTypeAheadController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Lot'),
      ),
      suggestionsCallback: (pattern) async {
        return await _loadInventoryLots(pattern);
      },
      itemBuilder: (context, Lot suggestion) {
        return Column(
          children: [
            ListTile(
              title: Text(suggestion.label ?? ''),
              subtitle: suggestion.expiration_date == null
                  ? null
                  : Text(suggestion.expiration_date.toString()),
            ),
            const Divider(
              height: 2,
            )
          ],
        );
      },
      onSuggestionSelected: (Lot suggestion) {
        lotTypeAheadController.text = suggestion.label ?? '';
        Provider.of<ExitMovement>(context, listen: false)
            .setLot(index, 'lot_uuid', suggestion.uuid);
        Provider.of<ExitMovement>(context, listen: false)
            .setLot(index, 'lot_label', suggestion.label);
        Provider.of<ExitMovement>(context, listen: false)
            .setLot(index, 'unit_cost', suggestion.unit_cost);
      },
    );
  }

  Widget stockExitStartPage() {
    String formattedSelectedDate = formatDate(_selectedDate, _customDateFormat);

    Future _selectDate(BuildContext context) async {
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate, // Refer step 1
        firstDate: DateTime(2000),
        lastDate: DateTime(2030),
      );
      if (picked != null && picked != _selectedDate) {
        setState(() {
          _selectedDate = picked;
          formattedSelectedDate = formatDate(_selectedDate, _customDateFormat);
        });
      }
    }

    return Column(
      children: <Widget>[
        ElevatedButton.icon(
          onPressed: () => _selectDate(context).then(
            (_) {
              Provider.of<ExitMovement>(context, listen: false).setDate =
                  _selectedDate;
            },
          ),
          icon: const Icon(Icons.date_range_sharp),
          label: Text(formattedSelectedDate),
        ),
        TextFormField(
          controller: _txtQuantity,
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
            labelText: "Nombre d'items",
          ),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return "Veuillez saisir le nombre des items";
            }
            return null;
          },
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly
          ],
        ),
      ],
    );
  }

  Widget lotExitPage(int index) {
    var txtQuantity = TextEditingController();
    var totalItems =
        Provider.of<ExitMovement>(context, listen: false).totalItems;
    return Column(
      children: <Widget>[
        Text('Item ${index + 1} sur $totalItems'),
        inventoryTypeaheadField(index),
        lotTypeaheadField(index),
        TextFormField(
          decoration: const InputDecoration(
            border: UnderlineInputBorder(),
            labelText: 'Quantity',
          ),
          onChanged: (value) {
            Provider.of<ExitMovement>(context, listen: false)
                .setLot(index, 'quantity', value);
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Veuillez saisir la quantité';
            }
            return null;
          },
          controller: txtQuantity,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly
          ],
        ),
      ],
    );
  }

  Widget submitPage() {
    var documentReference =
        Provider.of<ExitMovement>(context, listen: false).documentReference;
    var date = Provider.of<ExitMovement>(context, listen: false).date;
    var totalItems =
        Provider.of<ExitMovement>(context, listen: false).totalItems;
    var lots = Provider.of<ExitMovement>(context).lots;

    Future batchInsertMovements(var lots) async {
      var movementUuid = _uuid.v4();
      return lots.forEach((element) async {
        var movement = StockMovement(
          uuid: _uuid.v4(),
          movementUuid: movementUuid,
          depotUuid: _selectedDepotUuid,
          lotUuid: element['lot_uuid'],
          reference: documentReference,
          entityUuid: _selectedDepotUuid,
          periodId: int.parse(formatDate(date, [yyyy, mm])),
          userId: _userId,
          fluxId: _STOCK_FROM_TO_PATIENT,
          isExit: 1,
          date: date,
          description: 'Consommation',
          quantity: int.parse(element['quantity']),
          unitCost: element['unit_cost'].toDouble(),
        );
        await StockMovement.insertMovement(database, movement);
      });
    }

    Future<dynamic> save() {
      return batchInsertMovements(lots).then((value) {
        var snackBar = const SnackBar(
          content: Text('Sortie de stock réussie ✅'),
        );

        // Find the ScaffoldMessenger in the widget tree
        // and use it to show a SnackBar.
        ScaffoldMessenger.of(context).showSnackBar(snackBar);

        // reset the provider
        Provider.of<ExitMovement>(context, listen: false).reset();

        // back to home
        Navigator.pushNamed(context, '/');

        setState(() {
          _savingSucceed = true;
        });

        return true;
      });
    }

    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 0),
            child: Text('Date: ${formatDate(date, _customDateFormat)}'),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 0),
            child: Text('Reference: $documentReference'),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Nombre des items: $totalItems'),
          ),
          Expanded(
              child: ListView.builder(
            itemCount: lots.length,
            itemBuilder: (context, index) {
              if (lots.isNotEmpty && lots[index] != null) {
                var value = lots[index];
                return ListTile(
                  title: Text(value['inventory_text']),
                  subtitle: Text(value['lot_label']),
                  trailing: Chip(label: Text(value['quantity'])),
                );
              } else {
                return Row();
              }
            },
          )),
          ElevatedButton.icon(
            onPressed: () => save(),
            icon: const Icon(Icons.check_circle),
            label: const Text('Confirmer'),
          ),
        ],
      ),
    );
  }
}
