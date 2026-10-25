import 'package:flutter/material.dart';

import '../../../services/api_services.dart';

class ContractDropdown extends StatefulWidget {
  final Function(String contractId, Map<String, dynamic> contractData) onSelected;
  final String? initialValue;
  final String? entityId;

  const ContractDropdown({super.key, required this.onSelected, this.initialValue, this.entityId});

  @override
  State<ContractDropdown> createState() => _ContractDropdownState();
}

class _ContractDropdownState extends State<ContractDropdown> {
  List<Map<String, dynamic>> contracts = [];
  String? selectedContractId;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchContracts();
  }

  @override
  void didUpdateWidget(ContractDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entityId != widget.entityId) {
      selectedContractId = null;
      _fetchContracts();
    }
  }

  Future<void> _fetchContracts() async {
    setState(() => isLoading = true);
    try {
      final contracts = await ApiService.getContractsForDropdown(entityId: widget.entityId);
      setState(() {
        this.contracts = contracts;
        if (widget.initialValue != null && contracts.isNotEmpty) {
          final match = contracts.where((c) => c['uid'] == widget.initialValue);
          if (match.isNotEmpty) {
            selectedContractId = widget.initialValue;
          }
        }
         if (selectedContractId == null && contracts.length == 1) {
           selectedContractId = contracts.first['uid'] as String?;
           if (selectedContractId != null) {
             widget.onSelected(selectedContractId!, contracts.first);
           }
         }
         isLoading = false;
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      debugPrint("Error fetching contracts: $e");
    }
  }

  String _contractDisplayName(Map<String, dynamic> contract) {
    final num = contract['contractNumber'] ?? '';
    final name = contract['contractName'] ?? '';
    final type = contract['contractType'] ?? '';
    return '$num - $name ($type)';
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    // If auto-selected or only 1 contract, show it directly without dropdown
    if (selectedContractId != null && contracts.length <= 1) {
      return Text(
        contracts.isNotEmpty 
          ? '${contracts.first['contractNumber']} - ${contracts.first['contractName']} (${contracts.first['contractType']})'
          : 'No contract assigned',
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: contracts.isEmpty ? Colors.grey[600] : Colors.black87,
        ),
      );
    }
    
    return DropdownButtonFormField<String>(
      // Show placeholder only if multiple contracts exist
      hint: contracts.length > 1 ? const Text("Select Contract") : null,
      isExpanded: true,
      value: selectedContractId,
      items: contracts
        .where((c) => c['uid'] != null)
        .map<DropdownMenuItem<String>>((contract) {
          final uid = contract['uid'] as String;
          return DropdownMenuItem<String>(
            value: uid,
            child: Text(_contractDisplayName(contract)),
          );
        }).toList(),
      onChanged: (value) {
        setState(() => selectedContractId = value);
        if (value != null) {
          final match = contracts.firstWhere((c) => c['uid'] == value);
          widget.onSelected(value, match);
        }
      },
      decoration: InputDecoration(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
