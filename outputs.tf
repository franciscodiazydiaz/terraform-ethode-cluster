output "endpoint" {
  description = "Public endpoint to expose Geth and Prio Load Balancer endpoints"
  value       = "http://${aws_lb.alb.dns_name}"
}
