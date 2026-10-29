一元二次方程 \(ax^2+bx+c=0\)（\(a\neq 0\)）的求根公式是

\[
x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}
\]

下面用**配方法**推导。

---

## 1. 从一般形式出发

\[
ax^2+bx+c=0,\quad a\neq 
0
\]

两边除以 \(a\)：

\[
x^2+\frac ba x+\frac ca=0
\]

---

## 2. 把常数项移到右边

\[
x^2+\frac ba x=-\frac ca
\]

---

## 3. 配方

一次项系数是 \(\frac ba\)，它的一半是 \(\frac{b}{2a}\)，平方是 \(\frac{b^2}{4a^2}\)。

两边加上 \(\frac{b^2}{4a^2}\)：

\[
x^2+\frac ba x+\frac{b^2}{4a^2}
=
-\frac ca+\frac{b^2}{4a^2}
\]

左边正好是完全平方：

\[
\left(x+\frac{b}{2a}\right)^2
=
\frac{b^2}{4a^2}-\frac ca
\]

---

## 4. 右边通分

\[
\frac{b^2}{4a^2}-\frac ca
=
\frac{b^2}{4a^2}-\frac{4ac}{4a^2}
=
\frac{b^2-4ac}{4a^2}
\]

所以

\[
\left(x+\frac{b}{2a}\right)^2
=
\frac{b^2-4ac}{4a^2}
\]

---

## 5. 开平方

\[
x+\frac{b}{2a}
=
\pm\frac{\sqrt{b^2-4ac}}{2a}
\]

这里要求 \(b^2-4ac\ge 0\)，否则在实数范围内无解。

---

## 6. 移项得到求根公式

\[
x=-\frac{b}{2a}\pm\frac{\sqrt{b^2-4ac}}{2a}
\]

合并分母：

\[
\boxed{x=\frac{-b\pm\sqrt{b^2-4ac}}{2a}}
\]

---

## 判别式的作用

令

\[
\Delta=b^2-4ac
\]

则：

- \(\Delta>0\)：有两个不相等的实根；
- \(\Delta=0\)：有两个相等的实根，即
  \[
  x=-\frac{b}{2a}
  \]
- \(\Delta<0\)：在实数范围内无解，在复数范围内有两个共轭复根。

---

## 总结

推导的核心步骤是：

\[
ax^2+bx+c=0
\Rightarrow
\left(x+\frac{b}{2a}\right)^2
=
\frac{b^2-4ac}{4a^2}
\]

再开平方、移项，就得到求根公式。