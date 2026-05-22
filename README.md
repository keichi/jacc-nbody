# JACC.jl N体ベンチマーク

[JACC.jl](https://github.com/JuliaGPU/JACC.jl) を用いた、N体問題（直接総当たり法）の
力カーネルベンチマーク。**単一ソースのまま** CPU スレッド / CUDA / AMDGPU / Metal /
oneAPI のいずれのバックエンドでも動作する。

カーネルは [ymiki-repo/nbody](https://github.com/ymiki-repo/nbody) の
2次 leapfrog・直接総当たり (direct all-pairs, O(N²)) の加速度計算 `calc_acc` を参考にした。
本ベンチマークは同リポジトリの `BENCHMARK_MODE` に倣い、**力（加速度）計算カーネル
単体の性能**を、N を変えながら測定する。

## アルゴリズム

- 加速度: `a_i = Σ_j m_j (r_j - r_i) / (r_ji² + ε²)^{3/2}`、重力定数 `G = 1`
- Plummer ソフトニング: `ε = 1/64`
- 初期条件: 一様球（半径 1、総質量 1、等質量粒子）
- 相互作用あたり **24 FLOP**（reciprocal-sqrt を 4 FLOP と数える）
- データ配置: SoA（位置 `x,y,z`、質量 `m`、加速度 `ax,ay,az` を別配列）

## 必要環境

- Julia 1.11 以降

## セットアップ

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
```

## 実行

CPU スレッドバックエンド（既定。追加インストール不要）:

```sh
# 既定スイープ: N = 1024 .. 2^20、11 点
julia --project -t auto nbody_jacc.jl

# 引数で N_min N_max N_bins を指定
julia --project -t auto nbody_jacc.jl 1024 2097152 12
```

倍精度（`Float64`）に切り替え（既定は `Float32`）:

```sh
JACC_NBODY_FP=64 julia --project -t auto nbody_jacc.jl
```

## GPU バックエンドで実行

一度だけバックエンドを設定すると `LocalPreferences.toml` が生成される。
以降はスクリプトを無改変で実行できる。

```sh
# 例: CUDA。"amdgpu" / "metal" / "oneapi" も同様
julia --project -e 'import JACC; JACC.set_backend("cuda")'
julia --project nbody_jacc.jl
```

CPU スレッドへ戻す場合:

```sh
julia --project -e 'import JACC; JACC.set_backend("threads")'
```

## 出力

- 実行時に小規模 (N=256) の正当性チェックを行い、ホスト側の素朴な逐次実装と
  相対 L2 誤差を比較する。
- N スイープの各点で、最小計測時間 (0.5 s) に達するまで反復回数を自動調整し、
  `interactions/s` と `GFLOP/s` を表形式で出力する。

```
           N    iters      time[s]     interactions/s      GFLOP/s
        1024     2048       1.0448         2.0553e+09       49.328
        ...
peak performance: 54.217 GFLOP/s  (24 FLOP per interaction)
```

## ファイル

| ファイル | 内容 |
|---|---|
| `nbody_jacc.jl` | ベンチマーク本体（カーネル・初期条件・正当性チェック・スイープ） |
| `Project.toml` / `Manifest.toml` | 依存パッケージ（`JACC`） |
