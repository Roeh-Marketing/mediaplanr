# the description of a plan is stable

    Code
      cat(describe_plan(agency(), top_n = 3, as_json = TRUE))
    Output
      {
        "identity": {
          "name": "Q4-Q1 national digital",
          "nickname": "",
          "id": "plan_agency",
          "parent_id": null,
          "status": "",
          "approved_on": null,
          "objective": "",
          "author": null,
          "edits": []
        },
        "shape": {
          "grain": ["channel", "partner", "campaign", "tactic", "month"],
          "time_col": "month",
          "time_basis": "month",
          "tz": "",
          "flight_start": "2026-10-01",
          "flight_end": "2027-03-31",
          "n_line_items": 9,
          "n_rows": 54,
          "is_topline": false,
          "subplan_cells": []
        },
        "money": {
          "spend_basis": "",
          "total": 1320600,
          "spend_by": {
            "channel": {
              "top": [
                {
                  "value": "Streaming",
                  "spend": 600000,
                  "share": 0.4543
                },
                {
                  "value": "Programmatic",
                  "spend": 510000,
                  "share": 0.3862
                },
                {
                  "value": "Online Video",
                  "spend": 210600,
                  "share": 0.1595
                }
              ],
              "other": {
                "n_values": 0,
                "spend": 0
              }
            },
            "partner": {
              "top": [
                {
                  "value": "DSP A",
                  "spend": 360000,
                  "share": 0.2726
                },
                {
                  "value": "Stream A",
                  "spend": 360000,
                  "share": 0.2726
                },
                {
                  "value": "Stream B",
                  "spend": 240000,
                  "share": 0.1817
                }
              ],
              "other": {
                "n_values": 3,
                "spend": 360600
              }
            },
            "campaign": {
              "top": [
                {
                  "value": "Brand",
                  "spend": 990600,
                  "share": 0.7501
                },
                {
                  "value": "Promo",
                  "spend": 330000,
                  "share": 0.2499
                }
              ],
              "other": {
                "n_values": 0,
                "spend": 0
              }
            },
            "tactic": {
              "top": [
                {
                  "value": "Prospecting",
                  "spend": 780000,
                  "share": 0.5906
                },
                {
                  "value": "Upfront",
                  "spend": 360000,
                  "share": 0.2726
                },
                {
                  "value": "Retargeting",
                  "spend": 120000,
                  "share": 0.0909
                }
              ],
              "other": {
                "n_values": 2,
                "spend": 60600
              }
            }
          }
        },
        "commitments": {
          "committed": 360000,
          "floor_locked": 90000,
          "flexible": 810600,
          "headroom": 870600,
          "n_bounded_line_items": 3
        },
        "units": [
          {
            "unit_type": "impression",
            "planned_units": 118584415.58,
            "planned_spend": 1320600,
            "rate": 11.1364
          }
        ],
        "time": [
          {
            "month": "2026-10",
            "spend": 264120
          },
          {
            "month": "2026-11",
            "spend": 286130
          },
          {
            "month": "2026-12",
            "spend": 220100
          },
          {
            "month": "2027-01",
            "spend": 154070
          },
          {
            "month": "2027-02",
            "spend": 176080
          },
          {
            "month": "2027-03",
            "spend": 220100
          }
        ],
        "targetable": {
          "values": {
            "channel": {
              "top": ["Streaming", "Programmatic", "Online Video"],
              "n_more": 0
            },
            "partner": {
              "top": ["DSP A", "Stream A", "Stream B"],
              "n_more": 3
            },
            "campaign": {
              "top": ["Brand", "Promo"],
              "n_more": 0
            },
            "tactic": {
              "top": ["Prospecting", "Upfront", "Retargeting"],
              "n_more": 2
            }
          },
          "periods": {
            "column": "month",
            "first": "2026-10-01",
            "last": "2027-03-01",
            "n_values": 6
          }
        }
      }

# the description of a scenario is stable

    Code
      cat(describe_plan(agency_scenario(), top_n = 3, as_json = TRUE))
    Output
      {
        "identity": {
          "name": "Move to regional",
          "nickname": "s1",
          "id": "plan_s1",
          "parent_id": "plan_agency",
          "status": "in development",
          "approved_on": null,
          "objective": "Shift programmatic to regional streaming",
          "author": "agent",
          "edits": ["transfer", "scale"]
        },
        "shape": {
          "grain": ["channel", "partner", "campaign", "tactic", "month"],
          "time_col": "month",
          "time_basis": "month",
          "tz": "",
          "flight_start": "2026-10-01",
          "flight_end": "2027-03-31",
          "n_line_items": 9,
          "n_rows": 54,
          "is_topline": false,
          "subplan_cells": []
        },
        "money": {
          "spend_basis": "",
          "total": 1348341.9,
          "spend_by": {
            "channel": {
              "top": [
                {
                  "value": "Streaming",
                  "spend": 665160.9,
                  "share": 0.4933
                },
                {
                  "value": "Programmatic",
                  "spend": 472581,
                  "share": 0.3505
                },
                {
                  "value": "Online Video",
                  "spend": 210600,
                  "share": 0.1562
                }
              ],
              "other": {
                "n_values": 0,
                "spend": 0
              }
            },
            "partner": {
              "top": [
                {
                  "value": "Stream A",
                  "spend": 360000,
                  "share": 0.267
                },
                {
                  "value": "DSP A",
                  "spend": 322581,
                  "share": 0.2392
                },
                {
                  "value": "Stream B",
                  "spend": 305160.9,
                  "share": 0.2263
                }
              ],
              "other": {
                "n_values": 3,
                "spend": 360600
              }
            },
            "campaign": {
              "top": [
                {
                  "value": "Brand",
                  "spend": 983654,
                  "share": 0.7295
                },
                {
                  "value": "Promo",
                  "spend": 364687.9,
                  "share": 0.2705
                }
              ],
              "other": {
                "n_values": 0,
                "spend": 0
              }
            },
            "tactic": {
              "top": [
                {
                  "value": "Prospecting",
                  "spend": 773054,
                  "share": 0.5733
                },
                {
                  "value": "Upfront",
                  "spend": 360000,
                  "share": 0.267
                },
                {
                  "value": "Retargeting",
                  "spend": 107527,
                  "share": 0.0797
                }
              ],
              "other": {
                "n_values": 2,
                "spend": 107760.9
              }
            }
          }
        },
        "commitments": {
          "committed": 360000,
          "floor_locked": 90000,
          "flexible": 838341.9,
          "headroom": 898341.9,
          "n_bounded_line_items": 3
        },
        "units": [
          {
            "unit_type": "impression",
            "planned_units": 116173866.67,
            "planned_spend": 1348341.9,
            "rate": 11.6062
          }
        ],
        "time": [
          {
            "month": "2026-10",
            "spend": 269668.38
          },
          {
            "month": "2026-11",
            "spend": 292140.75
          },
          {
            "month": "2026-12",
            "spend": 224723.65
          },
          {
            "month": "2027-01",
            "spend": 157306.55
          },
          {
            "month": "2027-02",
            "spend": 179778.92
          },
          {
            "month": "2027-03",
            "spend": 224723.65
          }
        ],
        "targetable": {
          "values": {
            "channel": {
              "top": ["Streaming", "Programmatic", "Online Video"],
              "n_more": 0
            },
            "partner": {
              "top": ["Stream A", "DSP A", "Stream B"],
              "n_more": 3
            },
            "campaign": {
              "top": ["Brand", "Promo"],
              "n_more": 0
            },
            "tactic": {
              "top": ["Prospecting", "Upfront", "Retargeting"],
              "n_more": 2
            }
          },
          "periods": {
            "column": "month",
            "first": "2026-10-01",
            "last": "2027-03-01",
            "n_values": 6
          }
        }
      }

