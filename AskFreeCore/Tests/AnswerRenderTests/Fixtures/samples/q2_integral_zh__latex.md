用**分部积分**，取 \(u=x\)、\(dv=e^x dx\)，则 \(du=dx\)、\(v=e^x\)：

\[
\int x e^x\,dx = x e^x - \int e^x\,dx = x e^x - e^x + C = e^x(x-1)+C
\]

要点：
1. 选 \(u=x\) 是因为求导后 \(x\) 消失，积分变简单。
2. 结果求导验证：\((e^x(x-1))' = e^x(x-1)+e^x = xe^x\)，正确。