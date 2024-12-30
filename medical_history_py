from pyspark.sql import SparkSession
from pyspark.sql.functions import explode, col, concat_ws

# Initialize Spark session
spark = SparkSession.builder \
    .appName("Flatten JSON for Azure SQL") \
    .getOrCreate()

# Load the source data (replace '/path/to/source.json' with your actual path)
source_data = spark.read.json("/FileStore/rakdataset/patient_1.json", multiLine=True)

# Flatten the DataFrame and convert array column to string
flattened_df = source_data \
    .withColumn("medical_history", explode(col("medical_history"))) \
    .select(
        col("patient_id"),
        col("name"),
        col("age"),
        col("gender"),
        col("address.city"),
        col("address.state"),
        col("address.zip_code"),
        col("medical_history.condition"),
        col("medical_history.diagnosis_date"),
        concat_ws(",", col("medical_history.medications")).alias("medications")
    )

# Display the flattened DataFrame
display(flattened_df)

# Define Azure SQL Database connection properties
jdbc_url = "jdbc:sqlserver://sqldbserver01.database.windows.net:1433;database=hierarchy"
db_properties = {
    "user": "admina",
    "password": "Centurylink@123",
    "driver": "com.microsoft.sqlserver.jdbc.SQLServerDriver"
}

# Write the DataFrame to Azure SQL Database table
flattened_df.write \
    .format("jdbc") \
    .option("url", jdbc_url) \
    .option("dbtable", "medical_history") \
    .options(**db_properties) \
    .mode("overwrite") \
    .save()
