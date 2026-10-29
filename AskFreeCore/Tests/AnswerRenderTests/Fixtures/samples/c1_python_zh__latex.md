用 `pandas` 最直接，几行就能完成。

### 示例代码

```python
import pandas as pd

# 读取 CSV
df = pd.read_csv("data.csv")

# 按 "category" 列分组，对 "value" 列求平均值
result = df.groupby("category")["value"].mean()

print(result)
```

### 说明

1. **`groupby("category")`** 指定分组列，`["value"]` 指定要计算的列，`mean()` 求平均。
2. 结果是一个以分组值为索引的 **Series**；想保留成表格用 `result.reset_index()`。
3. 想一次对多列求平均，去掉 `["value"]`，直接 `df.groupby("category").mean()`（只对数值列生效）。
4. 分组列有缺失值时默认会被丢弃，需要保留可加 `dropna=False`。

### 不用 pandas 的版本

如果环境里没有 pandas，用标准库也能做：

```python
import csv
from collections import defaultdict

sums = defaultdict(float)
counts = defaultdict(int)

with open("data.csv", newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        key = row["category"]
        sums[key] += float(row["value"])
        counts[key] += 1

averages = {k: sums[k] / counts[k] for k in sums}
print(averages)
```

这个版本需要自己处理空值和类型转换，数据量大或逻辑复杂时还是建议用 pandas。