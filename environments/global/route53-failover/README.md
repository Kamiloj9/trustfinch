# Route 53 CA endpoint failover

Pass the ALB DNS names and hosted-zone IDs from the two independently applied regional stacks. The primary and secondary records use Route 53 alias target health; test a regional endpoint failure before advertising the global CA FQDN.
