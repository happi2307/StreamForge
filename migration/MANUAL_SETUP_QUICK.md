# StreamForge Phase 6 - Manual Setup Guide

See the full manual setup guide in the migration folder for detailed AWS Console steps required before running Terraform.

## Quick Reference

**Manual steps required:**
1. Provision Oracle source database (RDS or EC2)
2. Load Oracle schema and enable supplemental logging
3. Store credentials in AWS Secrets Manager
4. Install and run AWS Schema Conversion Tool (SCT)
5. Deploy converted PostgreSQL schema to Aurora
6. Update Terraform variables (dev.tfvars)
7. Deploy infrastructure with Terraform
8. Test DMS endpoints
9. Start DMS replication task

**Estimated time:** 1.5-2 hours

For detailed instructions, see: [migration/docs/manual-setup-guide.md](migration/docs/manual-setup-guide.md)
