# Kubernetes helper scripts

`k8s` Stow package 通过 `just stow k8s` 将可执行脚本链接到 `~/.local/bin`, 将仅用于
`source` 的 `kube-config-selector.sh` 链接到 `~/.local/lib`.

## `kube-config-selector.sh`

通过交互式菜单设置当前 shell 的 `KUBECONFIG` 环境变量. `~/.kube` 下的配置文件以 `.conf`
结尾; 在 `~/.bash_aliases` 中添加:

```sh
test -r "${HOME}/.local/lib/kube-config-selector.sh" && {
    alias kc='source "${HOME}/.local/lib/kube-config-selector.sh"'
}
```

使用时直接输入 `kc`, 再输入集群菜单前的数字序号即可.

> 小提醒: 新增 AWS 管理的 EKS 集群时, 可以先 `touch` 一个空 `.conf` 文件, 用 `kc` 选中它,
> 再执行 `aws eks update-kubeconfig`, 避免将所有集群配置混写进当前的 `KUBECONFIG` 或
> `~/.kube/config` 中.

## `kube-dump.sh`

批量导出 Kubernetes 资源 manifest 到 `./kube-dump` (可用 `-o DIR` 指定), 过程中使用
`jq` 清理重新导入其他集群时不需要的运行时字段以及 Rancher 自定义字段.

Secrets 会以明文导出, 输出文件权限为 `0600`, 目录权限为 `0700`.

## `kube-iperf3.sh`

轻量的全节点 iperf3 mesh, 适合临时排查节点间吞吐. 如果需要更完整的 hostNetwork、多流或
回归对比测试, 建议使用 [k8s-netperf](https://github.com/cloud-bulldozer/k8s-netperf).

## `manifests/k8s/rbac/readers.yaml`

提供 `svc-reader` 与 `deploy-reader` 两套 namespace 级只读 RBAC 预设 (有意省略
`metadata.namespace`, 由 `-n` 控制目标命名空间):

```sh
kubectl -n <namespace> apply -f manifests/k8s/rbac/readers.yaml
```
