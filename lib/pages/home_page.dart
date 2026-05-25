import 'package:flutter/material.dart';
import '../services/api_service.dart'; // 确保你的 api_service.dart 文件路径是这个

class HomePage extends StatefulWidget {
  // [优化] 遵循最佳实践，为 Widget 添加 key
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // [修复1]: 不再使用 late，直接初始化为空列表。
  // 这样即使API请求失败或返回空，_data.length 也是 0，UI 不会因空指针而崩溃。
  List<String> _data = [];

  // [修复2]: 增加专门的变量来管理加载和错误状态，让UI逻辑更清晰。
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 页面一加载就开始获取数据
    _fetchData();
  }

  // [修复3]: 改造异步请求方法，增加健壮的 try-catch 错误处理机制。
  Future<void> _fetchData() async {
    // 每次请求前，重置状态为"加载中"，方便下拉刷新等场景
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 假设你的 ApiService 返回一个 Future<List<String>>
      final items = await ApiService.fetchItems();
      
      // [关键] 检查 Widget 是否还存在于界面上，防止页面已关闭但 setState 仍在调用。
      if (mounted) {
        setState(() {
          _data = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      // 如果发生任何错误（网络、解析等），捕获它。
      if (mounted) {
        setState(() {
          _error = '数据加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('首页'),
        actions: [
          // [优化] 增加一个刷新按钮，方便用户主动刷新
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
        ],
      ),
      // [修复4]: 将UI构建逻辑拆分，根据不同状态（加载中、出错、数据为空、正常）显示不同界面。
      body: _buildBody(),
    );
  }

  // 专门用于构建主体的 Widget
  Widget _buildBody() {
    if (_isLoading) {
      // 状态一：正在加载中
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      // 状态二：发生错误
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchData,
              child: const Text('点击重试'),
            )
          ],
        ),
      );
    }

    if (_data.isEmpty) {
      // 状态三：数据为空
      return const Center(
        child: Text('暂无数据，请稍后重试'),
      );
    }

    // 状态四：一切正常，显示数据列表
    return ListView.builder(
      itemCount: _data.length,
      itemBuilder: (context, index) {
        return ListTile(
          leading: CircleAvatar(child: Text('${index + 1}')),
          title: Text(_data[index]),
        );
      },
    );
  }
}
