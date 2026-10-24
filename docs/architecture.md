# Architecture and reuse decisions

~~~mermaid
flowchart LR
  AURL["127.0.0.1:8080"] --> A["A · existing php-flaws-demo · unchanged"]
  subgraph K["Existing Kind cluster php-flaws-demo"]
    A
    subgraph B["B · lab-cve-109619"]
      BV["Vulnerable PHP 8.4.26 · cozybear profile"]
      BNET["B-only NetworkPolicy"]
      BV --- BNET
    end
    subgraph C["C · lab-php2shell"]
      CV["PHP 8.4.26 Bookworm · eness profile"]
      CNET["C-only NetworkPolicy"]
      CV --- CNET
    end
    T["trendmicro-system · reserved; no sensor"]
  end
  PortB["127.0.0.1:8081"] --> BV
  PortC["127.0.0.1:8083"] --> CV
~~~

## Reuse

- A keeps its existing app code, image, namespace, Deployment, Service and Kind cluster.
- B uses only the vulnerable PHP 8.4.26 image and target configuration from cozybear-dev's reference. Its automated attacker and corrected target are excluded.
- C has a separate Dockerfile and separate PHP/Apache configuration derived from the eness README's default `bookworm` profile. It does not inherit B's lab configuration. The source repository does not provide a runnable target Compose/Dockerfile; this repository supplies a target harness for the README-declared profile.
- Both build pinned official PHP 8.4.26 Apache images and use distinct image tags, Deployments, Services, namespaces and NetworkPolicies.
- Docker Compose remains a local reproduction mechanism. Kind runs the built images loaded into the existing node with `imagePullPolicy: Never`.
- Neither PoC nor attacker service is included or started. No remediation profile is part of this phase.

## Isolation and differences

B and C use independent namespaces and ClusterIP Services. Their host access uses localhost-only background port-forwards at 8081 and 8083. NetworkPolicies deny egress and restrict ingress to same-namespace traffic on TCP/8080. `verify-kind-labs.sh` samples C-to-B blocking with a harmless health request; this is evidence for that path, not a full network audit.

Both workloads use UID/GID 33, drop capabilities, disallow privilege escalation, use RuntimeDefault seccomp, read-only root filesystems and bounded in-memory runtime directories. These isolation settings are for the lab harness; the server and PHP settings are maintained separately for each reference profile.

## TrendAI disposition

`trendmicro-system` is an empty reserved namespace. The installed cluster runs Kubernetes 1.31.2 on a Kind node in WSL2; the support assessment found it unsuitable for an in-support Vision One evaluation. No sensor was installed. See [the assessment](trendai-container-security.md).
