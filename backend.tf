terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket6565434334320987547"  # Имя бакета S3, который мы создали для хранения состояния.
    key            = "terraform/state"  # Путь к файлу состояния в бакете S3. Так захотелось                                             
    region         = "eu-central-1"  # Регион, где расположен мой S3 бакет и DynamoDB таблица- там у меня и VPC
    dynamodb_table = "terraform-lock"  # Имя таблицы DynamoDB, которую мы  создали для блокировок.
    encrypt        = true  # Включает шифрование файлов состояния в S3 для обеспечения безопасности данных.
  }
