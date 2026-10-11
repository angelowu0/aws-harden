# Harbour Books — Base Stack

Recreates the three-tier bookstore stack from class: `harbour-books-vpc` with a public
EC2 instance (Nginx reverse-proxying a Flask app, both via Docker Compose) and a
private RDS MySQL instance. This exists so `../harbour-books-security/` has a real
stack to remediate — it's provisioned in the *insecure* starting state the security
review is meant to catch (see below), not as a template for how to run production
infrastructure.

## Layout

- `app/` — the Flask app, Dockerfile, `docker-compose.yml`, and `nginx.conf`. Shipped
  to the EC2 instance via user-data in `05-launch-ec2.sh`.
- `config.sh` — region, CIDRs, instance sizes, and tags. Fill in the `REPLACEME`
  values before running anything.
- `scripts/01`–`05` — provision the stack in order (networking → security groups → IAM
  role → RDS → EC2). `scripts/run-all.sh` runs all five with a confirmation prompt.
- `scripts/teardown.sh` — deletes everything this folder created. Run
  `harbour-books-security/scripts/teardown.sh` first if you applied that stack too.

## What gets built

- **Networking**: one VPC, 2 public subnets (routed to an Internet Gateway, for the
  EC2 instance) and 2 private subnets (no internet route — RDS subnet groups require
  2+ AZs even for a single-AZ instance, and the DB has no reason to reach the internet).
- **Security groups**: `ec2-sg` (ingress 80 from anywhere, 22 from your IP if set) and
  `rds-sg` (ingress 3306 from `ec2-sg` only, not publicly reachable).
- **IAM**: `harbour-books-ec2-role`, attached to the instance via an instance profile.
  It only gets `AmazonSSMManagedInstanceCore` (so you can reach the box through Session
  Manager instead of opening SSH wider than necessary) — no Secrets Manager access at
  this stage.
- **RDS**: a `db.t3.micro` MySQL instance, private, single-AZ.
- **EC2**: an Amazon Linux 2023 `t3.micro` instance. User-data installs Docker +
  Compose, writes the `app/` files, and runs `docker compose up -d --build`.

## The intentional starting gaps

This stack is built to match the story's "before" state on purpose, so the scripts in
`../harbour-books-security/` have something real to fix:

- `ec2-sg`'s outbound rule is left at AWS's default allow-all — not narrowed here.
- The RDS master password is generated in `04-create-rds.sh` and written straight into
  a plaintext `.env` file on the EC2 box by `05-launch-ec2.sh` (mode 600, but still a
  cleartext credential on disk) — not stored in Secrets Manager.
- No CloudWatch alarms or SNS notifications exist yet.

Do not treat this as a secure reference deployment — that's the whole point of the
follow-on remediation.

## Running it

```bash
cd harbour-books-base
$EDITOR config.sh              # fill in AWS_REGION, MY_IP_CIDR, KEY_PAIR_NAME, etc.
./scripts/run-all.sh           # provisions 01-05 in order
```

Requires `aws` CLI (v2, authenticated) and `openssl`. Takes roughly 10-15 minutes,
mostly waiting on RDS to become available. Once it's up, verify with:

```bash
curl http://<public-ip>/            # -> {"status":"ok","service":"harbour-books"}
curl http://<public-ip>/health/db   # -> {"status":"ok","db":"reachable"}
```

Then proceed to `../harbour-books-security/` to close the three gaps above. When
you're done with the exercise, tear down with `./scripts/teardown.sh` (run the
security stack's teardown first) to avoid leaving billable resources running in the
class account.
