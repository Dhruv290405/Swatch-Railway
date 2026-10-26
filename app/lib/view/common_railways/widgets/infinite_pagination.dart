import 'package:flutter/material.dart';

class PaginationWidget extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final Function(int) onPageChanged;
  final int pageSize;
  final int totalCount;
  final String? label;

  const PaginationWidget({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
    this.pageSize = 50,
    this.totalCount = 0,
    this.label,
  });

  int get startItem => (currentPage - 1) * pageSize + 1;
  int get endItem => (currentPage * pageSize).clamp(1, totalCount);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Page info
          Text(
            label ?? 'Showing $startItem-$endItem of $totalCount',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 13,
            ),
          ),
          // Page buttons
          Row(
            children: [
              if (currentPage > 1)
                _buildPageButton(context, currentPage - 1, Icons.navigate_before, 'Previous'),
              if (currentPage > 1 && currentPage <= 3)
                _buildPageButton(context, 1, Icons.check_circle, '1'),
              if (currentPage > 3 && totalPages > 5)
                _buildEllipsis(),
              if (currentPage > 3 && totalPages > 5)
                _buildPageButton(context, currentPage - 1, Icons.navigate_before, (currentPage - 1).toString()),
              if (currentPage > 2 && totalPages > 5)
                _buildPageButton(context, currentPage, Icons.check_circle, currentPage.toString()),
              if (currentPage < totalPages)
                _buildEllipsis(),
              if (currentPage < totalPages - 1 && totalPages > 5)
                _buildPageButton(context, totalPages, Icons.check_circle, totalPages.toString()),
              if (currentPage < totalPages)
                _buildPageButton(context, currentPage + 1, Icons.navigate_next, 'Next'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEllipsis() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: SizedBox(
        width: 20,
        height: 20,
        child: Center(
          child: Text(
            '...',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _buildPageButton(BuildContext context, int page, IconData icon, String label) {
    return InkWell(
      onTap: () => onPageChanged(page),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
