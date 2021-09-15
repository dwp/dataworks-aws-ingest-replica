# Adding / Removing Collections

The list of collections to be processed per environment is stored in the 
dataworks-secrets repository, and job tracking information is stored in 
the `intraday-job-status` table.

### Adding a collection
1. Ensure that impact to the pipeline is assessed:
   - How much historical data is to be processed?  A one-off cluster could be run 
      to process historical data, to avoid affecting the BAU intraday process
   - What is the volume of incrementals compared to the existing pipeline?  The
      cluster may need to be scaled


2. Add the collection name to the intraday secret

If historical data is not required, add a row to the tracking table using the 
`ProcessedDataEnd` property to set the start date.

### Removing a collection
1. Remove the collection name from the intraday secret
   
1. Optionally remove the data from S3 and drop the external table from the 
   intraday database.  If doing so, also delete all rows for this collection in
   the `intraday-job-status` table to prevent unexpected behaviour if the collection
   is re-added.
