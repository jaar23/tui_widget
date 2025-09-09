import tui_widget, json

# Sample JSON data for testing
let sampleJson = """
{
  "name": "John Doe",
  "age": 30,
  "address": {
    "street": "123 Main St",
    "city": "New York",
    "zipcode": "10001"
  },
  "hobbies": [
    "reading",
    "swimming",
    "coding"
  ],
  "active": true,
  "balance": 1234.56,
  "contacts": [
    {
      "name": "Jane Smith",
      "phone": "555-1234",
      "email": "jane@example.com"
    },
    {
      "name": "Bob Johnson",
      "phone": "555-5678",
      "email": "bob@example.com"
    }
  ]
}
"""

let sampleJson2 = """
{
  "metadata": {
    "rov": {
      "mode": 0,
      "collaborator_ids": {}
    },
    "usage": {
      "last_updated_at": "2018-11-12T15:33:34Z",
      "last_updater_id": "iam-ServiceId-12345___",
      "last_update_time": 1542036814782,
      "last_accessed_at": "2018-11-12T15:33:34Z",
      "last_access_time": 1542036814782,
      "last_accessor_id": "iam-ServiceId-12345___",
      "access_count": 0
    },
    "name": "Sample.csv",
    "description": "Simple csv file for experiment for getting started document.",
    "tags": [],
    "asset_type": "data_asset",
    "origin_country": "united states",
    "rating": 0,
    "total_ratings": 0,
    "catalog_id": "c6f3cbd8-2b7f-42fb-aa60-___",
    "created": 1541526321437,
    "created_at": "2018-11-06T17:45:21Z",
    "owner_id": "IBMid-___",
    "size": 9238,
    "version": 2,
    "asset_state": "available",
    "asset_attributes": [
      "data_asset",
      "data_profile"
    ],
    "asset_id": "45f4ab8c-37d5-45a1-8adf-___",
    "asset_category": "USER"
  },
  "entity": {
    "data_asset": {
      "mime_type": "text/csv",
      "dataset": true,
      "columns": [
        {
          "name": "Name",
          "type": {
            "type": "varchar",
            "length": 1024,
            "scale": 0,
            "nullable": true,
            "signed": false
          }
        },
        {
          "name": "Number",
          "type": {
            "type": "varchar",
            "length": 1024,
            "scale": 0,
            "nullable": true,
            "signed": false
          }
        }
      ]
    },
    "data_profile": {
      "971e9c66-be4c-44b4-91f3-___": {
        "metadata": {
          "guid": "971e9c66-be4c-44b4-91f3-___",
          "asset_id": "971e9c66-be4c-44b4-91f3-___",
          "dataset_id": "45f4ab8c-37d5-45a1-8adf-___",
          "url": "https://api.dataplatform.cloud.ibm.com/v2/data_profiles/971e9c66-be4c-44b4-91f3-___?catalog_id=c6f3cbd8-2b7f-42fb-aa60-___&dataset_id=45f4ab8c-37d5-45a1-8adf-___",
          "catalog_id": "c6f3cbd8-2b7f-42fb-aa60-___",
          "created_at": "2018-11-12T15:32:53.902Z",
          "accessed_at": "2018-11-12T15:32:53.902Z",
          "owner_id": "IBMid-___",
          "last_updater_id": "IBMid-___"
        },
        "entity": {
          "data_profile": {
            "options": {
              "disable_profiling": false,
              "max_row_count": 5000,
              "max_distribution_size": 100,
              "max_numeric_stats_bins": 200,
              "classification_options": {
                "disabled": false,
                "use_all_ibm_classes": true,
                "ibm_class_codes": [],
                "custom_class_codes": []
              }
            },
            "execution": {
              "status": "finished",
              "is_supported": true,
              "dataflow_id": "3f1ace02-4d40-451d-9bc7-___",
              "dataflow_run_id": "f774f92f-5a61-49ca-8a68-___"
            },
            "columns": [],
            "attachment_id": "8d614be0-6900-403b-ab50-___"
          }
        },
        "href": "https://api.dataplatform.cloud.ibm.com/v2/data_profiles/971e9c66-be4c-44b4-91f3-___?catalog_id=c6f3cbd8-2b7f-42fb-aa60-___&dataset_id=45f4ab8c-37d5-45a1-8adf-___"
      },
      "attribute_classes": [
        "NoClassDetected",
        "Organization Name"
      ]
    }
  },
  "attachments": [
    {
      "id": "b8c7a390-e857-4c34-add8-___",
      "version": 2,
      "asset_type": "data_asset",
      "name": "remote",
      "description": "remote",
      "connection_id": "070e9be2-40a8-4e0e-___",
      "connection_path": "catalogforgettingsta-datacatalog-r1s___/data_asset/Sample_SyjEQUy6m.csv",
      "create_time": 1541526323713,
      "size": 0,
      "is_remote": true,
      "is_managed": false,
      "is_referenced": false,
      "is_object_key_read_only": false,
      "is_user_provided_path_key": true,
      "transfer_complete": true,
      "is_partitioned": false,
      "complete_time_ticks": 1541526323713,
      "user_data": {},
      "test_doc": 0,
      "usage": {
        "access_count": 0,
        "last_accessor_id": "IBMid-___",
        "last_access_time": 1541526323713
      }
    },
    {
      "id": "8d614be0-6900-403b-ab50-___",
      "version": 2,
      "asset_type": "data_profile",
      "name": "data_profile_971e9c66-be4c-44b4-91f3-___",
      "object_key": "data_profile_971e9c66-be4c-44b4-91f3-___",
      "create_time": 1542036813627,
      "size": 9238,
      "is_remote": false,
      "is_managed": false,
      "is_referenced": true,
      "is_object_key_read_only": false,
      "is_user_provided_path_key": true,
      "transfer_complete": true,
      "is_partitioned": false,
      "complete_time_ticks": 1542036813627,
      "user_data": {},
      "test_doc": 0,
      "handle": {
        "bucket": "catalogforgettingsta-datacatalog-r1s___",
        "location": "us-geo",
        "key": "data_profile_971e9c66-be4c-44b4-91f3-___",
        "upload_id": "done",
        "max_part_num": 1
      },
      "usage": {
        "access_count": 0,
        "last_accessor_id": "iam-ServiceId-12345___",
        "last_access_time": 1542036813627
      }
    }
  ],
  "href": "https://api.dataplatform.cloud.ibm.com/v2/assets/45f4ab8c-37d5-45a1-8adf-___?catalog_id=c6f3cbd8-2b7f-42fb-aa60-___"
}
"""

# Create JSON viewer widget
var jsonViewer = newJsonViewer(1, 1, 50, 25, 
                              title="JSON Viewer", 
                              jsonData=sampleJson,
                              bgColor=bgBlack, 
                              fgColor=fgWhite)

var jsonViewer2 = newJsonViewer(1, 1, 50, 25, 
                              title="JSON Viewer", 
                              jsonData=sampleJson2,
                              bgColor=bgNone, 
                              fgColor=fgWhite)

# Add custom event handlers
jsonViewer.on("preupdate", proc(jv: JsonViewer, args: varargs[string]) =
  # Custom logic before each update
  discard
)

jsonViewer.on("postupdate", proc(jv: JsonViewer, args: varargs[string]) =
  # Custom logic after each update
  discard
)

# Create terminal app and add the JSON viewer
var app = newTerminalApp()

# Add the JSON viewer to the app
app.addWidget(jsonViewer, 0.3, 1.0)
app.addWidget(jsonViewer2, 0.7, 1.0)

# Run the application
app.run()