计算 \(\int x e^x\,dx\)，用**分部积分法**：

\[
\int u\,dv = uv - \int v\,du
\]

令：
- \(u = x\)，则 \(du = dx\)
- \(dv = e^x\,dx\)，则 \(  v = e^x\)

代入：

\[
\int x e^x\,dx = x e^x - \int e^x\,dx = x e^x - e^x + C
\]

所以：

\[
\boxed{\int x e^x\,dx = e^x(x-1) + C}
\]

其中 \(C\) 为任意常数。