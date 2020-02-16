# ExMustache Benchmark

Running benchmark scripts

```shell
mix run bench/run.exs
```


### Result

Configuration
```
Operating System: macOS
CPU Information: Intel(R) Core(TM) i7-8750H CPU @ 2.20GHz
Number of Available Cores: 12
Available memory: 16 GB
Elixir 1.7.4
Erlang 22.1.1

Benchmark suite executing with the following configuration:
warmup: 2 s
time: 10 s
memory time: 2 s
parallel: 1
inputs: none specified
Estimated total run time: 28 s
```

#### 60 bytes template

Render
```
Name                          ips        average  deviation         median         99th %
render: ex_mustache      227.12 K        4.40 μs   ±843.06%        2.99 μs        8.99 μs
render: bbmustache       156.97 K        6.37 μs   ±425.69%        4.99 μs       13.99 μs

Comparison:
render: ex_mustache      227.12 K
render: bbmustache       156.97 K - 1.45x slower +1.97 μs

Extended statistics:

Name                        minimum        maximum    sample size                     mode
render: ex_mustache         1.99 μs    16223.99 μs         1.95 M                  2.99 μs
render: bbmustache          3.99 μs     9003.99 μs         1.43 M                  4.99 μs

Memory usage statistics:

Name                   Memory usage
render: ex_mustache         1.52 KB
render: bbmustache          3.30 KB - 2.18x memory usage +1.78 KB
```

Parse
```
Name                         ips        average  deviation         median         99th %
parse: ex_mustache       50.38 K       19.85 μs    ±92.74%          16 μs          99 μs
parse: bbmustache        47.73 K       20.95 μs    ±85.30%          19 μs          79 μs

Comparison:
parse: ex_mustache       50.38 K
parse: bbmustache        47.73 K - 1.06x slower +1.10 μs

Extended statistics:

Name                       minimum        maximum    sample size                     mode
parse: ex_mustache           14 μs        4610 μs       480.24 K                    16 μs
parse: bbmustache            17 μs        6535 μs       461.35 K                    18 μs

Memory usage statistics:

Name                  Memory usage
parse: ex_mustache         9.98 KB
parse: bbmustache          5.54 KB - 0.55x memory usage -4.44531 KB

```

#### 20KB template with positive block

Render
```
Name                          ips        average  deviation         median         99th %
render: ex_mustache       43.70 K       22.88 μs    ±69.88%       18.99 μs       76.99 μs
render: bbmustache        18.38 K       54.41 μs    ±40.76%       44.99 μs      131.99 μs

Comparison:
render: ex_mustache       43.70 K
render: bbmustache        18.38 K - 2.38x slower +31.53 μs

Extended statistics:

Name                        minimum        maximum    sample size                     mode
render: ex_mustache        15.99 μs     3869.99 μs       424.83 K                 18.99 μs
render: bbmustache         40.99 μs     1303.99 μs       180.96 K                 43.99 μs

Memory usage statistics:

Name                   Memory usage
render: ex_mustache        10.59 KB
render: bbmustache         34.46 KB - 3.26x memory usage +23.88 KB
```

Parse
```
Name                         ips        average  deviation         median         99th %
parse: bbmustache         2.48 K      403.03 μs     ±8.99%         394 μs         544 μs
parse: ex_mustache        2.40 K      417.42 μs    ±14.93%         397 μs         787 μs

Comparison:
parse: bbmustache         2.48 K
parse: ex_mustache        2.40 K - 1.04x slower +14.39 μs

Extended statistics:

Name                       minimum        maximum    sample size                     mode
parse: bbmustache           379 μs        1724 μs        24.73 K                   388 μs
parse: ex_mustache          346 μs        1087 μs        23.87 K                   395 μs

Memory usage statistics:

Name                  Memory usage
parse: bbmustache         46.93 KB
parse: ex_mustache       211.40 KB - 4.50x memory usage +164.47 KB
```

#### 20KB template with negative block (best case for ExMustache)

Render
```
Name                          ips        average  deviation         median         99th %
render: ex_mustache      761.18 K        1.31 μs  ±2978.77%           1 μs           4 μs
render: bbmustache       145.28 K        6.88 μs   ±248.18%           7 μs          11 μs

Comparison:
render: ex_mustache      761.18 K
render: bbmustache       145.28 K - 5.24x slower +5.57 μs

Extended statistics:

Name                        minimum        maximum    sample size                     mode
render: ex_mustache            0 μs    45612.00 μs         5.34 M                     1 μs
render: bbmustache          6.00 μs       10681 μs         1.34 M                     7 μs

Memory usage statistics:

Name                   Memory usage
render: ex_mustache        0.164 KB
render: bbmustache          8.22 KB - 50.10x memory usage +8.05 KB
```

Parse
```
Name                         ips        average  deviation         median         99th %
parse: bbmustache         2.58 K      387.84 μs    ±14.98%         377 μs         509 μs
parse: ex_mustache        2.31 K      432.20 μs    ±15.90%         417 μs      796.04 μs

Comparison:
parse: bbmustache         2.58 K
parse: ex_mustache        2.31 K - 1.11x slower +44.37 μs

Extended statistics:

Name                       minimum        maximum    sample size                     mode
parse: bbmustache        369.00 μs        2806 μs        25.69 K                   370 μs
parse: ex_mustache          367 μs        1305 μs        23.05 K                   413 μs

Memory usage statistics:

Name                  Memory usage
parse: bbmustache         42.35 KB
parse: ex_mustache       205.20 KB - 4.85x memory usage +162.85 KB
```
